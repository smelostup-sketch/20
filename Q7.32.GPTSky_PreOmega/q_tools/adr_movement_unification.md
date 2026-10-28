# ADR: Унификация мувмента (U1–U5) — Шаг 1
Статус: ПРИНЯТО заказчиком (2026-10-12, «план одобрен. Го»). Версия: Q7.14_RengarPreOmega.
Контекст: q_tools/cleanup_inventory.md ч.6 (отклонения U1–U7); дневник — changes.md.

## Проблема
Три независимых стека движения (игрок StateComponent 465 строк; враг EnemyController —
своя гравитация/поворот/velocity напрямую; манекен — третий мини-стек). Ядро движения
читает клавиатуру напрямую (KEY_W хардкод при настроенном Input Map). Способности
(dash/dodge/leap/stealth) — монолит без профиля существа. Требование заказчика:
«мувмент врагов и аватара игрока идентичен в базовых принципах; игрок может сменить
аватара и двигаться курицей без проблем (с ограничениями курицы)».

## Решение (слои)
```
Слой 0  CharacterBody3D + move_and_slide                     — общий всем (движок)
Слой 1  MovementShell (тонкий, единственный у любого существа)
        — приём MovementIntent от провайдера; ЕДИНСТВЕННЫЙ писатель кинематики:
          rotation.y (политика фейсинга), velocity (делегированием), move_and_slide(),
          кэш пола, маршрутизация действий, recovery-блендинг после рывков.
Слой 2  GroundLocomotion — съёмный модуль локомоции (гравитация/разгон/торможение/
        прыжок). Для летающих/плавающих — Flight/SwimLocomotion ВМЕСТО него (Шаг 2,
        seam заложен: интерфейс setup(shell)+apply(delta,intent,mode,recovery)).
Слой 3  MobilityAction-компоненты (DashComponent, DodgeComponent), LeapComponent,
        StealthComponent — опциональные соседи; «функции нет у существа» = узел не
        прикреплён И/ИЛИ флаг профиля can_*=false (двойной замок).
Данные  CreatureProfile (Resource, .tres): числа + матрица способностей. Один файл
        на вид; смена аватара = модель + библиотеки анимаций + профиль.
Ввод    IntentProvider: PlayerIntentComponent (Input Map + yaw камеры) /
        AIIntentComponent (EnemyController.move_state) — зеркало контракта боевого
        ядра: провайдер ОБЯЗАН подавать намерение, исполнитель отказывает по своим
        правилам (owner-agnostic).
```

## Контракт MovementIntent (полностью — в шапке MovementIntent.gd)
direction (input-space Vector2), yaw + has_yaw, facing_locked, speed_scale,
jump_requested (одноразовый), action_request ""|"dash"|"dodge" + action_dir,
freeze_horizontal (лок ввода игрока — скорость НЕ трогать), snap_stop (стан/лок/блок/
стоп врага — мгновенный ноль, preserves боевая читаемость).

## Ключевые решения и родословная чисел
1. **Поведение игрока сохранено 1:1** (приоритет — feel из Q7.12 10/10): направление
   по yaw камеры (провайдер Q7.12 переехал в PlayerIntentComponent), векторный
   move_toward, лок ввода = freeze_horizontal, dodge/dash = те же скорости/длительности
   (экспорты, прежние дефолты 12/0.2 и 18/0.15), double-tap окно 0.25, засада leap —
   без изменений формул.
2. **Фейсинг — единственный писатель MovementShell**, экспоненциальное сглаживание
   `1-exp(-rate*delta)` в физтик-тик (кадрово-независимо). Калибровка rate:
   игрок 12.0 (родословна: legacy lerp 12/s из ThirdPersonCamera._process, тот же τ;
   камера больше не пишет rotation.y); враг 25.9 (родословна: -ln(1-0.35)*60 —
   точный экспоненциальный эквивалент legacy веса 0.35/тик при 60 Гц).
   Замечание: перенос ПОВОРОТА в физтик-тик — не разморозка задачи C: C осталась в
   части physics_interpolation/рендера, которую не трогаем; траектория от фейсинга
   не зависит с Q7.12 (намерение = yaw камеры).
3. **Враг на едином ядре, feel сохранён калибровкой**: EnemyGruntProfile
   acceleration=deceleration=36.0 (родословна: legacy враг мгновенно ставил скорость;
   36 м/с² даёт разгон 0→3.0 за 0.083 с и пробег торможения ≤0.13 м — в пределах
   legacy-поведения; механизм тот же, что у игрока, числа — видовые). gravity 20,
   landing_damping 10 (унификация: у врага legacy было velocity.y=0 на полу мгновенно —
   различие ≤1 тика). can_* все false, speed 3.0 (legacy chase_speed),
   retreat — speed_scale=0.65 (legacy retreat_speed_multiplier, переехал в AIIntent).
4. **Манекен = раковина без провайдера** (нулевое намерение → стоит; гравитация держит
   на полу) — доказательство общности ядра; DummyEnemyController больше не пишет
   velocity/move_and_slide.
5. **Ввод — только через Input Map** (U3): move_forward/back/left/right, jump
   (уже были в project.godot, теперь реально используются) + новые dodge_left (Q),
   dodge_right (E). Хардкод KEY_* из движения исчез; physical keycode'ы — в маппинге.
6. **Совместимость API**: MovementShell предоставляет прежнюю поверхность
   StateComponent (is_leaping/is_stealthed/is_dodging/is_dashing/is_climbing/
   is_swimming, set_stealthed/set_leaping, get_leap_direction, jump_requested,
   movement_speed_multiplier→speed_multiplier, сигналы state_changed/action_started/
   action_ended) — потребители (AttackInputComponent, EnemyController, Perception,
   симы) меняют только путь узла StateComponent→MovementShell.
   ActionType переехал в MobilityAction (Perception обновлён механически — ИИ-логика
   заморожена, изменений поведения нет).
7. **Осознанные микро-изменения поведения** (задокументированы, проверяются симами):
   a) прыжок, запрошенный в полёте (в т.ч. во время leap), больше не копится до
      приземления (legacy: space во время leap давал авто-хоп по приземлении) —
      jump_requested одноразовый;
   b) физика врага больше не зависит от присутствия игрока (legacy: return до
      гравитации при невалидном игроке);
   c) разгон/торможение врага — инерционные (36 м/с²), а не мгновенные;
   d) поворот игрока сглаживается в физтик-тик (τ тот же, сэмплирование ровнее).

## Отклонённые альтернативы
- **Монолит с флагами** («всё зашито в базовый мувмент, часть функций отключена»):
  валиден для одной локомоционной семьи (LoL, UE CharacterMovement), но при полёте/
  плавании/лазании ветки if пронизывают каждую функцию; площадь регрессии = все
  существа сразу. Заказчик согласился на гибрид: раковина у всех, локомоция съёмная.
- **Полный ECS-рефактор**: избыточен для прототипа, ломает контракт боевого ядра.
- **Autoload-диспетчер движения**: скрытые зависимости, проблемы headless-стендов
  (прецедент GameLog, changes.md Q7.13 п.11).

## Критерии приёмки
1. sim_core 12/12, sim_block 20/20, sim_v7×3 hit+dmg, sim_leap 7/7, sim_speed 5/5,
   sim_telegraph 14/14, sim_settings 18/18, sim_spam без спама, sim_enemy SUMMARY
   без регресса.
2. diag_move STRAIGHT: X-отклонение 0.000000 м; MOUSE_OFFSET: стоп-дрейф −0.0°,
   angle(vel,cam) сходится на камеру.
3. sim_chicken (новый стенд): смена профиля игрока на ChickenProfile.tres →
   скорость ходьбы = профильная (не 6.0), dash/dodge ОТКАЗАНЫ с причиной
   profile_capability, прыжок = профильный jump_force, стелс в кусте не включается
   (can_stealth=false); возврат профиля Ренгара восстанавливает способности.
4. Ни одного Input.is_key_pressed/KEY_* в Scripts/Movement/ и у провайдеров
   (кроме Input Map-экшенов); grep-контроль.

## Шаг 2 (не сейчас)
FlightLocomotion/SwimLocomotion отдельными файлами при появлении первого
летающего/плавающего; allow_strafe из профиля подключается для четвероногих.
GroundLocomotion при этом не редактируется (open/closed).
