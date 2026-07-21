@tool
extends Node3D

const VARIANT_NAMES := [
	"1 - Current shell / coherent-lighting baseline",
	"2 - Free Artec church-facade scan (CC BY)",
	"3 - Original AI PBR relief (10 cm front + 72 cm reveals)",
	"4 - Dark interior framing / oversized open arches",
	"5 - Four-arch dark foreground / reference composition",
]

@export_enum("Current baseline", "Free Artec scan", "Original AI relief", "Dark interior / oversized arches", "Four-arch dark foreground") var starting_variant := 2

@onready var _variants: Array[Node3D] = [
	$Variants/CurrentBaseline,
	$Variants/ArtecScan,
	$Variants/AIRelief,
	$Variants/DarkOpeningsRelief,
	$Variants/FramicForegroundRelief,
]
@onready var _label: Label = $Interface/Margin/Panel/Rows/Variant

var _current_variant := 0


func _ready() -> void:
	set_variant(starting_variant)


func _unhandled_key_input(event: InputEvent) -> void:
	if not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_1:
			set_variant(0)
		KEY_2:
			set_variant(1)
		KEY_3:
			set_variant(2)
		KEY_4:
			set_variant(3)
		KEY_5:
			set_variant(4)
		KEY_LEFT:
			set_variant(posmod(_current_variant - 1, _variants.size()))
		KEY_RIGHT:
			set_variant(posmod(_current_variant + 1, _variants.size()))


func set_variant(index: int) -> void:
	_current_variant = clampi(index, 0, _variants.size() - 1)
	for variant_index in _variants.size():
		_variants[variant_index].visible = variant_index == _current_variant
	_label.text = VARIANT_NAMES[_current_variant]


func get_variant_name() -> String:
	return VARIANT_NAMES[_current_variant]
