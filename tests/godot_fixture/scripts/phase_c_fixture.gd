extends Node

signal health_changed(value: int)

var speed: float = 5.0
const DEFAULT_HP: int = 100


func _on_source_renamed() -> void:
	pass


func ping(value: int = 1) -> int:
	health_changed.emit(value)
	return value
