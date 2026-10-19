import Testing
@testable import PetCore

@Suite struct DragTrackerTests {
    @Test func smallMovementIsAClick() {
        var tracker = DragTracker(start: PetPoint(x: 100, y: 100), time: 0)
        tracker.move(to: PetPoint(x: 102, y: 101), time: 0.05)
        #expect(tracker.isDragging == false)
        #expect(tracker.end(time: 0.1) == .click)
    }

    @Test func movementBeyondThresholdIsADrag() {
        var tracker = DragTracker(start: PetPoint(x: 100, y: 100), time: 0)
        tracker.move(to: PetPoint(x: 110, y: 100), time: 0.05)
        #expect(tracker.isDragging)
    }

    @Test func releaseVelocityUsesRecentSamples() {
        var tracker = DragTracker(start: PetPoint(x: 0, y: 0), time: 0)
        tracker.move(to: PetPoint(x: 50, y: 0), time: 0.5)
        tracker.move(to: PetPoint(x: 60, y: 0), time: 0.55)
        tracker.move(to: PetPoint(x: 70, y: 0), time: 0.60)
        guard case let .drag(velocity) = tracker.end(time: 0.6) else {
            Issue.record("expected drag"); return
        }
        #expect(abs(velocity.x - 200) < 1)
        #expect(velocity.y == 0)
    }

    @Test func pausedBeforeReleaseHasNoVelocity() {
        var tracker = DragTracker(start: PetPoint(x: 0, y: 0), time: 0)
        tracker.move(to: PetPoint(x: 80, y: 0), time: 0.2)
        guard case let .drag(velocity) = tracker.end(time: 1.0) else {
            Issue.record("expected drag"); return
        }
        #expect(velocity == PetPoint(x: 0, y: 0))
    }
}
