extends Node

var _currency: int = 100

func get_currency() -> int:
	return _currency

func spend(amount: int) -> bool:
	if _currency < amount:
		return false
	_currency -= amount
	return true

func add(amount: int) -> void:
	_currency += amount
