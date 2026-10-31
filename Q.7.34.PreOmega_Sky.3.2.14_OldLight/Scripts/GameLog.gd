class_name GameLog
## GameLog — единый журнал игры (Q7.13, пункт 4 вердикта заказчика).
##
## Статический сервис-класс (НЕ autoload): глобальный class_name разрешается
## компилятором в любом контексте, включая headless-стенды --script, где
## autoload-идентификаторы на момент компиляции скрипта ещё не зарегистрированы
## (родословная: sim_telegraph.gd компилирует CombatComponent на загрузке).
##
## Все компоненты пишут ТОЛЬКО через GameLog (никаких прямых print в скриптах).
## Текст сообщений — на русском; протокольные токены (reason=locked_or_recovery,
## dir=LEFT, state=WAITING_DIRECTION и т.п.) сохраняются латиницей: это
## идентификаторы внутренних контрактов (шапка CombatComponent, enum'ы),
## а не декоративный текст.
##
## Режимы (владелец — SettingsService, ids debug_logging/verbose_logging
## сохранены для совместимости user://settings.cfg):
##   OFF      — журнал выключен («Журнал событий» = выкл);
##   COMPACT  — сжатый: только значимые события (старты/исходы/смерть/блок);
##   VERBOSE  — подробный: + отказы, хитбоксы, клипы, решения ИИ, кусты.
##
## Правило выбора уровня (родословная — расследование «пропал блок», Q7.12):
## диагностически важные события (ввод блока, отказы блока, исходы атак)
## ОБЯЗАНЫ быть в COMPACT — их потеря в логе однажды стоила заказчику
## ложной тревоги «блок пропал».
enum Mode { OFF, COMPACT, VERBOSE }

static var mode: Mode = Mode.COMPACT


## Сжатый уровень: значимые события.
static func compact(tag: String, message: String) -> void:
	if mode != Mode.OFF:
		print("[%s] %s" % [tag, message])


## Подробный уровень: технологические детали (отказы ядра, хитбоксы, клипы, ИИ).
static func verbose(tag: String, message: String) -> void:
	if mode == Mode.VERBOSE:
		print("[%s] %s" % [tag, message])
