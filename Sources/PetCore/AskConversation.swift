import Foundation

/// A quick-ask conversation with Claude: questions, streamed answers and the session for follow-ups.
public struct AskConversation: Equatable, Sendable {
    public enum State: Equatable, Sendable {
        case streaming
        case done
        case failed(String)
        case stopped
    }

    public struct Turn: Equatable, Sendable {
        public var question: String
        public var answer: String
        public var state: State
        public init(question: String, answer: String, state: State) {
            self.question = question
            self.answer = answer
            self.state = state
        }
    }

    /// Identifies one run's place: the conversation (bumped by "New") and the turn in it.
    public struct Ticket: Equatable, Sendable {
        public let epoch: Int
        public let turn: Int
    }

    public private(set) var turns: [Turn] = []
    /// Bumped on every reset, so late events from a previous conversation's run are dropped.
    public private(set) var epoch = 0
    /// The CLI session that holds this conversation, once the first answer reported it.
    public private(set) var sessionID: String?
    /// Session the turn in flight continues (`--resume`); nil for the first question.
    public private(set) var resumeID: String?

    public init() {}

    public var isStreaming: Bool { turns.last?.state == .streaming }
    public var canAsk: Bool { !isStreaming }

    public var lastAnswer: String? {
        turns.last.flatMap { $0.answer.isEmpty ? nil : $0.answer }
    }

    @discardableResult
    public mutating func ask(_ question: String) -> Bool {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canAsk, !trimmed.isEmpty else { return false }
        resumeID = sessionID
        turns.append(Turn(question: trimmed, answer: "", state: .streaming))
        return true
    }

    /// Index of the turn in flight, for binding a run's events to its own turn.
    public var currentTurn: Int? { isStreaming ? turns.count - 1 : nil }

    public var ticket: Ticket? { currentTurn.map { Ticket(epoch: epoch, turn: $0) } }

    public mutating func receive(session: String, ticket: Ticket? = nil) {
        guard ticket.map({ $0.epoch == epoch }) ?? true else { return }
        sessionID = session
    }

    /// After "No conversation found" on resume: carry on without the old context.
    public mutating func forgetSession() {
        sessionID = nil
    }

    public mutating func receive(text: String, ticket: Ticket) {
        guard ticket.epoch == epoch else { return }
        receive(text: text, turn: ticket.turn)
    }

    public mutating func complete(ticket: Ticket) {
        guard ticket.epoch == epoch else { return }
        complete(turn: ticket.turn)
    }

    public mutating func fail(_ message: String, ticket: Ticket) {
        guard ticket.epoch == epoch else { return }
        fail(message, turn: ticket.turn)
    }

    public mutating func cancel(ticket: Ticket) {
        guard ticket.epoch == epoch else { return }
        cancel(turn: ticket.turn)
    }

    /// `text` is the whole answer so far, not a delta. Without `turn`, applies to the turn in flight.
    public mutating func receive(text: String, turn: Int? = nil) {
        update(turn) { $0.answer = text }
    }

    public mutating func complete(turn: Int? = nil) {
        update(turn) { $0.state = .done }
    }

    public mutating func fail(_ message: String, turn: Int? = nil) {
        update(turn) { $0.state = .failed(message) }
    }

    public mutating func cancel(turn: Int? = nil) {
        update(turn) { $0.state = .stopped }
    }

    public mutating func reset() {
        let next = epoch + 1
        self = AskConversation()
        epoch = next
    }

    /// Changes only a turn that is still streaming; late events for finished turns are dropped.
    private mutating func update(_ turn: Int?, _ change: (inout Turn) -> Void) {
        let index = turn ?? turns.count - 1
        guard turns.indices.contains(index), turns[index].state == .streaming else { return }
        change(&turns[index])
    }
}
