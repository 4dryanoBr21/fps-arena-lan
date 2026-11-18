class_name HabitsPanel
extends Control
## Relatório do Treino adaptativo: os números que a IA guardou sobre o
## jogador deste aparelho (autoload Habits) e as dicas do que os bots estão
## explorando. Abre pelo menu. O botão de apagar pede confirmação (2 toques).

signal closed

var _confirming_reset: bool = false

@onready var stats_label: Label = %StatsLabel
@onready var tips_label: Label = %TipsLabel
@onready var status_label: Label = %StatusLabel
@onready var reset_button: Button = %ResetButton
@onready var close_button: Button = %CloseButton


func _ready() -> void:
	hide()
	reset_button.pressed.connect(_on_reset_pressed)
	UiFit.keep_fitted(self, $Center/Panel)
	close_button.pressed.connect(close)


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func open() -> void:
	_confirming_reset = false
	reset_button.text = "Apagar o aprendizado"
	status_label.text = ""
	_refresh()
	show()
	close_button.grab_focus()


func close() -> void:
	if not visible:
		return
	hide()
	closed.emit()


func _refresh() -> void:
	var profile := Habits.profile
	stats_label.text = "\n".join(profile.stats_lines())
	var training_map := ""
	for map: Dictionary in NetworkManager.MAPS:
		if map["mode"] == "training":
			training_map = map["path"]
	var tips := PackedStringArray()
	for tip in profile.insights(training_map):
		tips.append("• " + tip)
	tips_label.text = "\n\n".join(tips)


func _on_reset_pressed() -> void:
	if not _confirming_reset:
		_confirming_reset = true
		reset_button.text = "Toque de novo para apagar"
		status_label.text = "Os bots voltam a não saber nada sobre você."
		return
	Habits.reset()
	_confirming_reset = false
	reset_button.text = "Apagar o aprendizado"
	status_label.text = "Aprendizado apagado."
	_refresh()
