class_name AssetLoader
extends RefCounted
## Loads optional user art/sound at runtime, with caching and graceful
## failure: a missing or broken file returns null (and warns once), so callers
## fall back to the built-in shapes / silence.
##
## Paths may be res://, user://, absolute, or relative to the config file's
## folder (so you can keep an `art/` folder next to lucidin_chaos.json).

const IMAGE_EXTS := ["png", "jpg", "jpeg", "webp", "svg", "bmp", "tga"]
const AUDIO_EXTS := ["wav", "ogg", "mp3"]

var base_dir := "res://"
var _textures: Dictionary = {}
var _audio: Dictionary = {}
var _warned: Dictionary = {}


func _init(p_base_dir: String = "res://") -> void:
	base_dir = p_base_dir


func resolve(path: String) -> String:
	var p := path.strip_edges()
	if p == "":
		return ""
	if p.begins_with("res://") or p.begins_with("user://") or p.is_absolute_path():
		return p
	return base_dir.path_join(p)


## Returns a Texture2D, or null if path is empty or can't be loaded.
func load_texture(path: String) -> Texture2D:
	var full := resolve(path)
	if full == "":
		return null
	if _textures.has(full):
		return _textures[full]
	var tex: Texture2D = null
	var ext := full.get_extension().to_lower()
	if not (ext in IMAGE_EXTS):
		_warn_once(full, "unsupported image type '.%s'" % ext)
	elif full.begins_with("res://") and ResourceLoader.exists(full):
		var res: Resource = load(full)
		tex = res as Texture2D
	elif FileAccess.file_exists(full):
		var img := Image.load_from_file(full)
		if img != null and not img.is_empty():
			tex = ImageTexture.create_from_image(img)
	if tex == null:
		_warn_once(full, "sprite not found or unreadable; using fallback shape")
	_textures[full] = tex
	return tex


## Returns an AudioStream, or null if path is empty or can't be loaded.
func load_audio(path: String) -> AudioStream:
	var full := resolve(path)
	if full == "":
		return null
	if _audio.has(full):
		return _audio[full]
	var stream: AudioStream = null
	var ext := full.get_extension().to_lower()
	if not (ext in AUDIO_EXTS):
		_warn_once(full, "unsupported audio type '.%s' (use wav/ogg/mp3)" % ext)
	elif full.begins_with("res://") and ResourceLoader.exists(full):
		stream = load(full) as AudioStream
	elif FileAccess.file_exists(full):
		match ext:
			"wav":
				stream = AudioStreamWAV.load_from_file(full)
			"ogg":
				stream = AudioStreamOggVorbis.load_from_file(full)
			"mp3":
				stream = AudioStreamMP3.load_from_file(full)
	if stream == null:
		_warn_once(full, "sound not found or unreadable; playing nothing")
	_audio[full] = stream
	return stream


func _warn_once(path: String, msg: String) -> void:
	if _warned.has(path):
		return
	_warned[path] = true
	push_warning("[assets] %s: %s" % [path, msg])
