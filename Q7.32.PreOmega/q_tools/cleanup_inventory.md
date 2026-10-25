# ИНВЕНТАРЬ ЧИСТКИ + АУДИТ ЕДИНООБРАЗИЯ — база Q7.12.RengarPreOmega
Статус: ЖДЁТ ВЕРДИКТОВ ЗАКАЗЧИКА (по номерам пунктов). Ничего не удалено до вердикта.
Метод: полный обход дерева (find+grep), каждый пункт проверен по коду, не по handoff.

## Часть 0. Список мусора из PROJECT_HANDOFF устарел (честность)
- «мёртвый корневой AnimationComponent.gd (class_name AnimationComponent!)» — ОТСУТСТВУЕТ в дереве.
- «осиротевшие test_*.gd.uid» — ОТСУТСТВУЮТ: все .uid имеют пару .gd (проверено циклом).
- «DummyEnemy.gd:81 has_variable» — файла DummyEnemy.gd нет; grep has_variable по всему дереву = 0.
  Современный аналог проблемы — п.5 (мёртвый ролл блока в DummyEnemyController.take_dmg).
- «проверка от гпт» в комментариях — grep gpt = 0 совпадений.
- «emoji-печати» — print'ов с emoji нет; emoji ЖИВУТ в Label3D-индикаторах (телеграф ⚡/↑/←/→,
  статусы 🛡️💫❓❗🛑 у врага, 🛡️🎯 у манекена) — это ФУНКЦИОНАЛЬНЫЙ телеграф (Q7.9 опция B),
  а не мусор. Не удалять без замены (см. п.10-11 про вынос в компонент).
Вывод: базу 7.x заказчик/предшественник уже частично вычистили.

## Часть 1. Мёртвый код (рекомендация: УДАЛИТЬ)
1. EnemyController.gd ~45-51: цикл по группе dummy_enemy с телом `pass` — literally ничего не делает
   (комментарий «пропускаем манекены», но фильтрация целей давно в другом месте). Удаление безопасно.
2. Основная_сцена.tscn, узел PLayerCharacterBody3D/VisualModel/VisualModel_AnimationPlayer:
   AnimationPlayer с root_node="../VisualModel" → разрешается в несуществующий путь; никем не
   используется (MixamoAnimationLibrary и MixamoAnimationComponent берут AnimationPlayer из FBX).
   Мёртвый узел. (Родословная: diag_sliding_report.md, «Побочные находки».)
3. EnemyController.gd:23 `var player: Node3D = null` (член) — никогда не присваивается: в
   _physics_process объявляется ЛОКАЛЬНАЯ `var player` (44 строка), затеняющая член. Убрать член
   (или снять затенение) — на поведение не влияет.
4. EnemyController.gd:66-67 `elif combat_comp.ai_state == "STUNNED": combat_comp.ai_state = "IDLE"` —
   дубль: ядро CombatComponent._update_timers (179-180) уже сбрасывает STUNNED→IDLE по истечении
   stun_timer. Два владельца одного перехода = нарушение «единого источника». Удалить ветку в контроллере.
5. DummyEnemyController.gd take_dmg(): вызывает `is_blocking_active("")` — ВСЕГДА false
   (BLOCK_RESPONSE[""] не существует → сравнение "" == "LEFT/RIGHT/UP" ложно), НО с побочкой:
   каждый проход роллит randf()<0.95 и активирует enemy_block на 1.0 с. Итог: двойной ролл блока
   (первый — в контактном обработчике ядра, второй — здесь), недостижимый print BLOCK_SUCCESS,
   хаотично постоянно активный блок манекена. Фикс: убрать ролл из take_dmg — блок решается ОДИН
   раз в контактном пути ядра (как у врага). Это же закрывает дух пункта handoff про DummyEnemy.gd:81.
6. EnemyUtilityAIComponent._ready(): `_refresh_decision(true)` выполняется даже при utility_ai_enabled=false
   → фантомная строка «DECISION | APPROACH» в логе при старте сцены (наблюдается в симах).
   Низкий приоритет (цепь ИИ — материал пересборки, очередь 3): гейтить по enabled или оставить до пересборки.

## Часть 2. Костыли-заглушки VFX/SFX (рекомендация: ЗАМЕНИТЬ или УДАЛИТЬ до настоящих ассетов)
7. EnemyController._play_impact_sound(): на КАЖДЫЙ удар синтезирует белый шум — создаёт
   AudioStreamPlayer+AudioStreamGenerator, толкает 2205 случайных сэмплов, убивает узел через 0.1 с.
   Классический костыль. Замена: обычный AudioStreamPlayer3D с wav-ассетом (в Assets уже лежат
   block_success_*.wav — нужен impact-звук) или удалить до появления SFX.
8. EnemyController._spawn_impact_particles(): 5 кубов BoxMesh с твинами на каждый удар, спавн в
   tree.root (не в узел врага!). Замена: GPUParticles3D-компонент в сцене или удалить.
9. EnemyController._play_hit_flash(): подмена material_override на 0.15 с через await + СОСТЯЗАНИЕ:
   при двух перекрывшихся попаданиях второй вызов сохраняет flash-материал первого как «оригинал» →
   после восстановления модель может остаться КРАСНОЙ навсегда. Замена: через ModelTintComponent
   (он уже прикреплён к врагу и создан ровно для материалов модели) c API flash/restore — гонка уходит.

## Часть 3. Дубликаты (рекомендация: ВЫНЕСТИ В КОМПОНЕНТ)
10. _spawn_damage_label — БАЙТ-В-БАЙТ дубль в EnemyController.gd и DummyEnemyController.gd
    (цифра урона Label3D + billboard к камере + твин).
11. HP-бары (_create_enemy_hp_bar / _create_dummy_hp_bar — различаются цветом) и StateLabel-
    индикаторы (_update_enemy_indicator / _update_dummy_indicator — различаются набором emoji) —
   почти-дубли + создание UI-узлов в коде контроллера (отклонение от компонентной структуры).
    Рекомендация: один WorldIndicatorComponent (сцена/компонент): hp-бар + статус-символы +
    damage label, цвета/символы — экспорты (data-driven). Контроллеры перестают строить UI.
12. CombatComponent: _on_player_weapon_hitbox_body_entered и _on_enemy_weapon_hitbox_body_entered —
    почти идентичные блок-ветки (is_blocking_active → notify_successful_block → cancel/стан).
    ВНИМАНИЕ: это контракт единого ядра (Q2). Трогать ТОЛЬКО отдельной задачей после пересборки ИИ,
    с прогоном sim_core 12/12 + sim_block 20/20. Сейчас — фиксирую, не трогаю.

## Часть 4. Логирование (рекомендация: привести к стандарту Q4)
13. Ungated print (в обход _trace/debug_logging): StateComponent×7 (DODGE/DASH/STEALTH/BUSH),
    MixamoAnimationComponent×3, MixamoAnimationLibrary×1, EnemyAnimationComponent×1,
    DummyEnemyController×2, StacksComponent×1 (ULTIMATE_ACTIVATED), CombatDebugVisualizer×2,
    Player3d/EnemyController «[Player/Enemy] DEATH»×2.
    Стандарт Q4 уже существует в CombatComponent (_trace/_vtrace + экспорт debug_logging/verbose_logging,
    настройка «Журнал боя»). Рекомендация: тот же паттерн во все компоненты; DEATH-печати можно
    оставить (редкое событие) или тоже гейтить — на усмотрение.
    Примечание: расследование блока показало цену «стойких» настроек лога — единый стандарт снизит путаницу.

## Часть 5. Имена/файлы (рекомендация: переименовать/оставить)
14. HealtComponent.gd — опечатка имени ФАЙЛА (class_name внутри уже HealthComponent; все типы в коде уже корректны). Переименование файла + путь в 3 ext_resource сценах; .uid едет с файлом. Риск низкий,
    проверка: --import + sim_core/sim_v7.
15. q_tools: sim7_LEFT/RIGHT/UP.txt — архивные логи прогонов (ваши); *_out.txt — сырьё последних
    прогонов (перезаписываются). Рекомендация: архивы оставить как свидетельство, сырьё не трогать.
16. Assets/Mixamo: Jump.fbx, Run side.fbx, Running DASH.fbx НЕ используются в ANIMATION_SOURCES
    (Jump играет Running Jump.fbx). Вероятно — материал под будущие анимации dodge/dash/jump.
    Рекомендация: НЕ ТРОГАТЬ (ассеты заказчика).
17. Сцена_отладки_камеры.tscn, Сцена_реакции_на_удар.tscn — отладочные стенды с заглушками
    (VisualCube, без StateComponent). Оставить как стенды или в архив — на усмотрение.

## Часть 6. АУДИТ ЕДИНООБРАЗИЯ МУВМЕНТА (игрок / враг / смена аватара)
Цель заказчика (дословно): «мувмент врагов и аватара игрока должен быть идентичен в базовых
принципах, меняется только мувмент конкретного существа… игрок может менять аватара и двигаться
курицей без проблем (но с ограничениями курицы)».

### Текущее состояние (три независимых стека движения)
- ИГРОК: Player3d._physics_process → StateComponent.process() (edge-detect Q/E/double-tap, ЧИТАЕТ
  КЛАВИАТУРУ НАПРЯМУЮ Input.is_key_pressed(KEY_W…)) → apply_physics() (снова читает клавиши;
  направление — из yaw камеры через провайдер [Q7.12], разгон/торможение векторное, гравитация,
  landing_damping) → move_and_slide. Поворот корпуса: ThirdPersonCamera._process (lerp_angle 12/s).
- ВРАГ: EnemyController._physics_process — СВОЯ гравитация (на полу velocity.y=0.0 СРАЗУ, у игрока —
  landing_damping), СВОЙ поворот (lerp_angle 0.35 за тик к игроку), velocity пишется НАПРЯМУЮ
  (CHASE/RETREAT/STOPPED — без разгона/торможения, мгновенная скорость), свой move_and_slide.
  StateComponent прикреплён, но для движения НЕ используется (в _ready лишь мёртвое присваивание
  movement_speed_multiplier).
- МАНЕКЕН: DummyEnemyController — velocity=0, свой move_and_slide, свой UI в коде.

### Отклонения от единообразия (пронумерованы для вердикта)
U1. ДВЕ реализации физики движения вместо одной → разный feel (игрок с инерцией, враг — мгновенные
    скорости), дубли констант (gravity=20 в StateComponent И в EnemyController; speed-множители в двух местах).
U2. Ядро движения (StateComponent) знает про КЛАВИАТУРУ: Input.is_key_pressed внутри process() и
    apply_physics(). Для «курицы» и для ИИ ядро должно получать НАМЕРЕНИЕ, а не устройство.
U3. Input Map настроен (move_forward/move_back/move_left/move_right/jump в project.godot), но НЕ
    используется — везде хардкод KEY_W/KEY_A/KEY_S/KEY_D/KEY_SPACE/KEY_Q/KEY_E. Ребайндов нет.
U4. Поворот корпуса пишется в трёх местах тремя способами (камера._process рендер-рейтом; враг —
    физтик-тик lerp 0.35; манекен — никак). Нет единой политики фейсинга.
U5. Способности (dash/dodge/jump/leap/stealth) — монолит в StateComponent без профиля существа.
    «Курица не может рывок» сейчас невыразимо иначе как выковыриванием кода.
U6. UI (hp-бар, статус, damage label) создаётся в коде контроллеров (п.10-11).
U7. CombatComponent.ai_state — «ai_»-префикс в ОБЩЕМ ядре (есть и у игрока); по сути это is_stunned.

### Целевая архитектура (предложение, data-driven, под смену аватаров)
```
Устройство/ИИ            Намерение                Исполнение
PlayerIntentComponent ─┐  intent_dir: Vector2   ┌─ MovementCore (эволюция StateComponent):
 (Input Map actions,   ├─ intent_yaw: float ───►│   разгон/торможение/гравитация/пол,
  камера=yaw-провайдер)│  jump_requested: bool  │   dodge/dash/jump/leap — БЕЗ Input.*,
AIIntentComponent ─────┘  dodge/dash-запросы     │   всё через CreatureProfile
 (move_state врага →                              └─ CharacterBody3D.move_and_slide()
  вектор+yaw к цели)
CreatureProfile (Resource, на аватара): speed, acceleration, deceleration, gravity, jump_force,
  can_dash, can_dodge, can_leap, can_stealth, … → Ренгар: всё можно; Курица: can_dash=false и т.д.
FacingPolicy: ЕДИНСТВЕННЫЙ писатель rotation.y (провайдер yaw + калиброванное сглаживание);
  игрок — yaw камеры, враг — yaw к цели, курица — что угодно из того же механизма.
Смена аватара = подмена (модель + AnimationLibrary-маппинг + CreatureProfile). MovementCore не меняется.
```
Единый контракт намерения (по образцу единого ядра атаки Q2): провайдер ОБЯЗАН подавать намерение,
ядро его исполняет и отказывает по своим правилам (занято/восстановление/нет способности в профиле).

### Рекомендация по очерёдности
Унификацию (U1-U5) делать ОДНИМ заходом с пересборкой ИИ (очередь 3): AIIntentComponent — это и
есть провайдер намерения поверх единого ядра; делать раньше = делать дважды. Пункты 1-15 (чистка)
от унификации независимы и безопасны уже сейчас (каждый проверяется sim_core 12/12 + sim_v7×3 +
sim_block 20/20 + diag_move×2).
Тест-сценарий «курица» (критерий приёмки унификации): смена профиля игрока на куриный →
WASD/прыжок работают с параметрами курицы, double-tap dash ОТКАЗАН с причиной в логе
(способность отсутствует в профиле), враг на том же MovementCore преследует с той же моделью
инерции; sim-набор зелёный.
