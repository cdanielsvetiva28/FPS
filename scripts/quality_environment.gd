extends WorldEnvironment
## Applies the player's graphics quality (Game.graphics_quality) to this
## scene's environment, the viewport and shadows when the scene loads.
##
##   LOW     No SSAO/SSIL/glow, softer shadows, renders at 75% resolution
##           (upscaled with FSR).
##   MEDIUM  SSAO, glow, MSAA 2x.
##   HIGH    Adds SSIL, screen-space reflections, and (where this scene
##           allows it) SDFGI global illumination and volumetric fog.

## Enable SDFGI (bounced light) on High. Costly; worth it in enclosed levels.
@export var allow_sdfgi := false
## Enable volumetric fog (light shafts) on High.
@export var allow_volumetric_fog := false
@export var allow_ssr := false


func _ready() -> void:
	apply(Game.graphics_quality)


func apply(quality: int) -> void:
	var env := environment
	var high := quality >= Game.Quality.HIGH
	var medium := quality >= Game.Quality.MEDIUM
	env.ssao_enabled = medium
	env.glow_enabled = medium
	env.ssil_enabled = high
	env.ssr_enabled = high and allow_ssr
	env.sdfgi_enabled = high and allow_sdfgi
	env.volumetric_fog_enabled = high and allow_volumetric_fog

	var viewport := get_viewport()
	viewport.msaa_3d = Viewport.MSAA_2X if medium else Viewport.MSAA_DISABLED
	viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED if medium else Viewport.SCREEN_SPACE_AA_FXAA
	viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR if medium else Viewport.SCALING_3D_MODE_FSR
	viewport.scaling_3d_scale = 1.0 if medium else 0.75

	RenderingServer.directional_shadow_atlas_set_size(8192 if high else 4096 if medium else 2048, true)
	var soft := RenderingServer.SHADOW_QUALITY_SOFT_HIGH if high \
		else RenderingServer.SHADOW_QUALITY_SOFT_LOW if medium else RenderingServer.SHADOW_QUALITY_HARD
	RenderingServer.directional_soft_shadow_filter_set_quality(soft)
	RenderingServer.positional_soft_shadow_filter_set_quality(soft)
