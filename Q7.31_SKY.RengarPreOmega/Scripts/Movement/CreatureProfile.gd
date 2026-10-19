class_name CreatureProfile
extends Resource
## Профиль существа (Q7.14): ЧИСЛА движения + матрица способностей. Данные, не узел:
## один .tres шарится всеми экземплярами вида (Resource — ноль узлов на сущность).
## Смена аватара игрока = модель + библиотеки анимаций + профиль (+ вкл/выкл
## компонентов способностей); исполнитель движения не меняется.
##
## Родословная чисел — в changes.md (запись Q7.14) и ADR
## (q_tools/adr_movement_unification.md): значения перенесены из калиброванных
## экспортов legacy-StateComponent/EnemyController, новых «от балды» нет.
## Правка чисел = калибровка с замером (q_tools-стенды), не хардкод.

@export_group("Наземная локомоция")
@export var speed := 6.0                    # м/с целевой горизонтальной скорости
@export var acceleration := 10.0            # м/с² разгон к цели
@export var deceleration := 15.0            # м/с² торможение к нулю
@export var action_exit_deceleration := 36.0 # м/с² плавный выход из dash/dodge
@export var gravity := 20.0                 # м/с²
@export var jump_force := 8.0               # м/с вертикальный импульс прыжка
@export var landing_damping := 10.0         # м/с² гашение vy на полу
@export var facing_rate := 12.0             # 1/с экспоненциального сглаживания поворота корпуса

@export_group("Способности (двойной замок: флаг + прикреплённый компонент)")
@export var can_jump := true
@export var can_dash := true
@export var can_dodge := true
@export var can_leap := true
@export var can_stealth := true
@export var allow_strafe := true            # seam для четвероногих (Шаг 2; пока только данные)
