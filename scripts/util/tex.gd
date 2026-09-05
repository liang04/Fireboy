extends RefCounted
## 程序化贴图与调色板。
## 本工程不携带任何外部美术资源，所有可见内容都由代码生成：
## 好处是工程零依赖、可整体复制、随时换配色；代价是画面偏几何风格。
## 后续接入真实美术时，只需把 Tex.solid(...) 换成 load(...) 即可，其余代码不用动。

class_name Tex

# ---------------------------------------------------------------- 纹理缓存
## 同一 (颜色, 尺寸) 的纯色贴图只生成一次，后续全部命中复用。
## 收益：① 门装饰线、宝石/池子等大量重复贴图不再重复 new ImageTexture + 逐像素填充；
##       ② 重玩本关 / 切关时不再泄漏式地生成新纹理（旧纹理随节点释放，
##          但缓存命中后引用计数归零才会真正释放，整体内存更稳定）。
static var _cache: Dictionary = {}


# ---------------------------------------------------------------- 调色板
const C_STONE := Color("#4a5568")        # 石头地形
const C_WOOD := Color("#8a5a34")         # 木质平台
const C_FIRE := Color("#ff6b35")         # 火娃
const C_FIRE_DARK := Color("#c43e12")
const C_WATER := Color("#3aa8f0")        # 水娃
const C_WATER_DARK := Color("#1668b8")
const C_LAVA := Color("#ff8c1a")         # 岩浆
const C_POOL := Color("#2f9ee0")         # 水潭
const C_ACID := Color("#7ed321")         # 毒液
const C_GEM_RED := Color("#ff4d6d")
const C_GEM_BLUE := Color("#4dd2ff")
const C_PLATE_OFF := Color("#9aa5b1")
const C_PLATE_ON := Color("#ffd166")
const C_DOOR := Color("#b08d57")
const C_PLATFORM := Color("#6c7a89")
const C_BOX := Color("#a0783c")
const C_PORTAL := Color("#b46cff")
const C_EXIT := Color("#2b3440")


## 生成一张带高光/阴影边的纯色方块贴图（按 颜色+尺寸 缓存复用）
static func solid(color: Color, size: Vector2i) -> ImageTexture:
	var key := "%s|%d|%d" % [color.to_html(false), maxi(size.x, 1), maxi(size.y, 1)]
	if _cache.has(key):
		return _cache[key] as ImageTexture

	var img := Image.create(maxi(size.x, 1), maxi(size.y, 1), false, Image.FORMAT_RGBA8)
	var w: int = img.get_width()
	var h: int = img.get_height()
	img.fill(color)
	for x in w:
		img.set_pixel(x, 0, color.lightened(0.28))
		if h > 1:
			img.set_pixel(x, h - 1, color.darkened(0.38))
	for y in h:
		img.set_pixel(0, y, color.lightened(0.12))
		if w > 1:
			img.set_pixel(w - 1, y, color.darkened(0.22))
	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex


## 生成一个圆形（近似）多边形，用于水滴 / 宝石等装饰
static func circle_points(radius: float, segments: int = 16, center := Vector2.ZERO) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in segments:
		var a: float = TAU * float(i) / float(segments)
		pts.append(center + Vector2(cos(a), sin(a)) * radius)
	return pts


## 生成一个菱形（宝石形状）
static func diamond_points(rx: float, ry: float, center := Vector2.ZERO) -> PackedVector2Array:
	return PackedVector2Array([
		center + Vector2(0, -ry),
		center + Vector2(rx, 0),
		center + Vector2(0, ry),
		center + Vector2(-rx, 0),
	])


## 便捷：创建一个 Sprite2D（居中显示）
static func sprite(color: Color, size: Vector2i, centered := true) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = solid(color, size)
	s.centered = centered
	return s
