# M0 — заметки спайка

Дата: 2026-10-19. Claude Code 2.1.299 (бандл Claude.app), macOS 27.0.1, Swift 6.4 (только Command Line Tools), MacBook Pro M3 Pro.
Код спайков: [`spikes/m0`](../spikes/m0) (`swift build`, три executable: `PanelSpike`, `LayerSpike`, `TranslateSpike`).

## Итог по допущениям

| # | Допущение из ТЗ | Результат | Что меняем |
|---|---|---|---|
| 1 | Хуки срабатывают для desktop-сессий | ✅ Да, и без перезапуска сессий | Реестр создаёт сессию по **любому** событию, не только по `SessionStart` |
| 2 | Statusline даёт лимиты | ⚠️ Схема есть (`rate_limits.five_hour/seven_day`), но **statusline не запускается для desktop-сессий** | Основной источник лимитов — `rate_limit_event` из `claude -p` (см. №3) |
| 3 | `claude -p` подходит для быстрого вопроса | ✅ Да. Плюс отдаёт `rate_limit_event` с загрузкой 5 ч и 7 дн | Используем и для вопросов, и для замера лимитов |
| 4 | Прозрачная панель через SwiftPM без Xcode | ✅ Да. Окно не забирает фокус, 120 fps | — |
| 5 | Рендер на SpriteKit | ❌ Слишком тяжёлый: 2–8 % CPU, ~125 МБ | **Рендер на CALayer**: 0.1–0.2 % CPU, ~12 МБ |
| 6 | Геометрия чёлки | ⏸ Не проверено: ноутбук закрыт, работают 2 внешних монитора | «Нора» на внешнем мониторе — **основной сценарий**, а не запасной |
| 7 | Translation из SwiftPM-бинарника | ✅ API работает, ⚠️ языковые пакеты ru/en не скачаны (`notInstalled`) | Онбординг: попросить скачать пакеты. Скорость перевода замерить после этого |
| 8 | Стабильная подпись для TCC | ⚠️ Нет ни одного codesigning-сертификата | Self-signed сертификат создаёт пользователь (шаги ниже) |
| 9 | Хук быстрее 20 мс | ✅ `sh` + `nc -U`: медиана 9.5 мс, максимум 12 мс | Хук — shell-скрипт, без Swift-бинарника |

---

## 1. Хуки

Проверено временной установкой логирующего хука на 11 событий в `~/.claude/settings.json` (с бэкапом). После проверки хуки удалены, конфиг восстановлен и совпадает с бэкапом, лог удалён.

- **Desktop (Code tab)**: события пошли из текущей сессии сразу после правки `settings.json`. Пошли и из **других уже открытых** desktop-сессий, у которых `SessionStart` не было.
- **CLI (TUI и `-p`)**: срабатывают.
- **Общие поля**: `session_id`, `cwd`, `transcript_path`, `hook_event_name`, `permission_mode`, `prompt_id`, `effort`, `scratchpad_dir`.

| Событие | Свои поля |
|---|---|
| `SessionStart` | `source` (`startup`, …), `model` |
| `UserPromptSubmit` | `prompt` — **текст промпта, никогда не сохраняем** |
| `PreToolUse` | `tool_name`, `tool_input`, `tool_use_id`, `mcp_server` (для MCP) |
| `PostToolUse` | то же + `duration_ms`, `tool_response` |
| `Stop` | `last_assistant_message`, `background_tasks`, `session_crons`, `stop_hook_active` |
| `SubagentStop` | `agent_id`, `agent_type`, `agent_transcript_path`, … |
| `SessionEnd` | Видели для `-p`. Поля не разбирали |

**Наблюдения:**
- После каждого `Stop` в CLI приходит `SubagentStop`: это служебный сабагент (post-turn summary). Его нельзя считать «сабагентом пользователя». Фильтруем по `agent_type` или учитываем только сабагенты между `SubagentStart` и `SubagentStop`.
- В **auto mode** запросов разрешений почти нет, поэтому `Notification(permission_prompt)` — редкий сигнал «ждёт ввода». Дополнительные сигналы: `PreToolUse` для `AskUserQuestion` и `ExitPlanMode` (ждёт до соответствующего `PostToolUse`) и `Notification(idle_prompt)`.
- **Не наблюдали** (не было условий): `Notification`, `StopFailure`, `SubagentStart`, `PreCompact`. Поля этих событий уточним в M2, на живых сессиях.
- **Окружение**: хук наследует env процесса `claude`, так что `PIXELPET_INTERNAL=1` работает. `CLAUDE_CODE_ENTRYPOINT` тоже наследуется (из этой сессии пришло `claude-desktop`), поэтому по нему нельзя различать источник.
- Путь unix socket ограничен ~104 байтами. `~/.pixelpet/pet.sock` подходит, путь в scratchpad — нет.

## 2. Statusline

- Схема statusline в CLI 2.1.299 (из встроенной документации бинарника): `model.{id,display_name}`, `context_window.{used_percentage,remaining_percentage,context_window_size,…}`, `rate_limits.five_hour.{used_percentage,resets_at}`, `rate_limits.seven_day.{…}`, `effort.level`, `thinking.enabled`, `prompt_cache.*`, `workspace.*`.
- `rate_limits` есть «только для подписчиков». Аккаунт — Claude Team, поэтому должны быть.
- **Для desktop-сессий statusline не вызывается**: за время теста от трёх desktop-сессий не пришло ни одного события statusline. Живой payload из TUI снять не удалось: сессию заблокировал диалог «Try the new fullscreen renderer?».
- **Вывод**: statusline остаётся источником модели и контекста **только для терминальных сессий**. Для desktop-сессий модель берём из `SessionStart.model`, а контекст в v1 не показываем (или оцениваем по transcript).

## 3. `claude -p`

- Бинарник: `~/Library/Application Support/Claude/claude-code/<version>/<hash>/claude.app/Contents/MacOS/claude`. В `PATH` его нет. Версия и хеш меняются при обновлении, поэтому `ClaudeLocator` ищет по шаблону и берёт самую новую версию.
- Рабочая команда для быстрого вопроса:
  ```
  claude -p "<вопрос>" --model haiku --tools "" --setting-sources project \
    --output-format stream-json --verbose --include-partial-messages --no-session-persistence
  ```
  - `--tools ""` — без инструментов.
  - `--setting-sources project` — **не грузит пользовательские хуки**, авторизация по подписке работает. Это надёжнее env-маркера, оставляем оба.
  - `--bare` **не подходит**: требует `ANTHROPIC_API_KEY`, OAuth подписки не использует.
  - Для follow-up вместо `--no-session-persistence` используем `--resume <session_id>`.
- **Тайминги (haiku)**: `init` через 1.7 с, первый токен через 2.7 с, конец ответа ~2.7 с. Потом ещё ~1.4 с до `result`: в это время приходит `post_turn_summary`. UI считает ответ готовым по `message_stop`, не дожидаясь `result`.
- Стоимость: ~$0.002 за короткий запрос.
- **`rate_limit_event`** в stream-json:
  ```json
  {"type":"rate_limit_event","rate_limit_info":{"status":"allowed","rateLimitType":"five_hour",
   "unifiedWindows":{"five_hour":{"utilization":0.07,"resetsAt":1792416600},
                     "seven_day":{"utilization":0.04,"resetsAt":1792688400}}}}
  ```
  Это **основной источник лимитов**: приходит с каждым быстрым вопросом. Если вопросов не было, раз в 30 мин делаем фоновый «пинг» (только пока есть активные агенты или открыта панель). Цена — копейки, а лимит тратится пренебрежимо мало.

## 4. Окно и рендер

| Вариант | CPU (top, установившийся) | RAM |
|---|---|---|
| SpriteKit, 120 fps, постоянная анимация | 8.3 % | ~125 МБ |
| SpriteKit, 12 fps | 2.3 % | ~124 МБ |
| SpriteKit, `isPaused` | ~4 % (сцена продолжает тикать) | ~125 МБ |
| **CALayer, смена кадра по таймеру 12 fps** | **0.2 %** | **~12 МБ** |
| **CALayer + `CABasicAnimation` (прыжок) поверх** | **0.1 %** | **~12 МБ** |

- **Решение: CALayer.** Кадры спрайта — это `CGImage`, мы подставляем их в `layer.contents` по таймеру своей частоты для каждого состояния. Перемещение, прыжки и пружины делает Core Animation: оно рендерится в render server вне процесса, плавно на 120 Гц и почти без CPU.
- `NSPanel` с `.borderless, .nonactivatingPanel`, уровнем `.statusBar` и `canJoinAllSpaces/fullScreenAuxiliary/stationary` работает, окно не становится key.
- Сборка SwiftPM: нужен `swift-tools-version:6.2`, чтобы задать `.macOS(.v26)`. Предупреждения `ld: search path … not found` от CLT безвредны.

## 5. Экраны и чёлка

```
screen Gigabyte M32U  2560×1440  maxFPS=120  notch=false
screen DELL P2419HC   1920×1080  maxFPS=60   notch=false
```
- Сейчас ноутбук закрыт, работают 2 внешних монитора. **Чёлки нет**, и, судя по всему, так бывает часто.
- Следствие для ТЗ: «нора» на внешнем мониторе — **основной** режим «дома», равноправный с чёлкой. Экран для дома выбирается настройкой (по умолчанию — экран с меню-баром).
- Учитываем разную частоту: 120 Гц и 60 Гц. Таймер кадров спрайта от частоты дисплея не зависит, Core Animation подстраивается сам.
- **Перепроверить с открытой крышкой**: `auxiliaryTopLeftArea/RightArea` и окно над меню-баром в зоне чёлки.

## 6. Перевод

- `TranslationSession(installedSource:target:)` компилируется и вызывается из SwiftPM-бинарника без SwiftUI.
- `NLLanguageRecognizer` правильно определил `ru` и `en`. `LanguageAvailability.status` = `supported`.
- Перевод падает с `notInstalled`: **языковые пакеты не скачаны**. Ставятся так: Системные настройки → Основные → Язык и регион → Языки перевода → русский и английский.
- Скорость перевода замерим после установки пакетов.

## 7. Подпись и разрешения

- `security find-identity -p codesigning`: 0 сертификатов.
- Для ad-hoc подписи TCC (Accessibility) привязывается к хешу бинарника, поэтому после каждой пересборки разрешение слетает. Это мешает на M5 (перевод выделения).
- Нужен self-signed сертификат «Pixel Pet Dev» для подписи кода. Создать его должен **пользователь**: это изменение связки ключей, я его не делаю.
  1. Связка ключей → меню «Связка ключей» → Ассистент сертификации → Создать сертификат.
  2. Имя `Pixel Pet Dev`, тип удостоверения «Самоподписанный корень», тип сертификата «Подписывание кода».
  3. После этого `scripts/bundle.sh` подписывает так: `codesign -s "Pixel Pet Dev"`.
- До M5 этот шаг не нужен.

## 8. Хук и задержка

- `sh` + `nc -U -w 1` → сокет: медиана 9.5 мс, максимум 12 мс. Если сервера нет — 8 мс, без ошибок.
- `python3` только на запуск тратит ~20 мс, поэтому в хуке не используем.
- `nc` есть в системе по умолчанию, ставить ничего не нужно.

## Открытые пункты, перенесённые в следующие этапы

- [ ] Живой payload statusline из TUI (нужно один раз ответить на диалог нового рендерера; проверять через `--settings`, без глобальной установки).
- [ ] Поля `Notification`, `StopFailure`, `SubagentStart`, `PreCompact` (M2).
- [ ] Чёлка при открытой крышке (M4).
- [ ] Скорость перевода после установки пакетов (M5).
- [ ] Self-signed сертификат (перед M5).
