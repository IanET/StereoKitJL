import LibStereoKit as SK
import Base.@kwdef
import LibStereoKit: vec2, vec3, quat, color128, char16_t # Base SK types

macro u8_str(s) reinterpret(Cchar, transcode(UInt8, s)) end
macro u16_str(s) reinterpret(char16_t, transcode(UInt16, s)) end

const appname = u8"Project"
const asset_folder = u8"assets"
const white = color128(1, 1, 1, 1)
const blueish = color128(0.5, 0.6, 0.7, 1.0)
const quat_identity = SK.quat(0, 0, 0, 1)
const cm2m = 0.01f0
const mm2m = 0.001f0
const rval = Ref(0.5f0)
const rval2 = Ref(0.5f0)

@kwdef mutable struct RenderState 
    ui_sprite::SK.sprite_t = SK.sprite_t(C_NULL)
    buffer::Vector{Cchar} = zeros(Cchar, 128)
    helmet::SK.model_t = SK.model_t(C_NULL)
    helmet_pos::Ref{vec3} = Ref(vec3(-0.25, 0, -0.5))
    helmet_ori::Ref{quat} = Ref(SK.quat_from_angles(20, 170, 0))
    helmet_scale::Ref{vec3} = Ref(vec3(0.2, 0.2, 0.2))
end

function render(rs::RenderState) 
    pose = SK.matrix_trs(rs.helmet_pos, rs.helmet_ori, rs.helmet_scale)
    SK.model_draw(rs.helmet, pose, white, SK.render_layer_0)
end

const grs = RenderState()
const render_grs() = render(grs)
const render_grs_c = @cfunction(render_grs, Nothing, ())

function renderloop(render_rs_c, sleeptime)
    while SK.sk_step(render_rs_c) > 0
        sleep(sleeptime)
    end
end

function initsk()
    settings = SK.sk_settings_t(
        pointer(appname),
        pointer(asset_folder),
        SK.display_mode_flatscreen,
        SK.display_blend_any_transparent,
        0,
        SK.depth_mode_balanced,
        SK.log_none,
        0, 0, 0, 0, 0, 0, 0, C_NULL, C_NULL)
    SK.sk_init(settings) 
end

function loadassets(rs::RenderState)
    rs.ui_sprite = SK.sprite_create_file(u8"StereoKitWide.png", SK.sprite_type_single, u8"default")
    rs.helmet = SK.model_create_file(u8"DamagedHelmet.gltf", SK.shader_t(C_NULL))
end

function main(rs::RenderState)
    initsk()
    loadassets(rs)

    renderloop(render_grs_c, isinteractive() ? 0.1 : 0.0)

    SK.sk_shutdown()
end

main(grs)
