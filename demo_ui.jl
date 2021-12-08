import LibStereoKit as SK
import Base.@kwdef

# Base SK types
import LibStereoKit: vec2, vec3, quat, color128, char16_t

macro u8_str(s) 
    [reinterpret(Cchar, c) for c in transcode(UInt8, s)] 
end
macro u16_str(s) 
    [reinterpret(char16_t, c) for c in transcode(UInt16, s)] 
end

const appname = u8"Project"
const asset_folder = u8"assets"
const white = color128(1, 1, 1, 1)
const blueish = color128(0.5, 0.6, 0.7, 1.0)
const quat_identity = SK.quat(0, 0, 0, 1)
const window_pose = SK.pose_t(vec3(0, 0.25, -0.25), SK.quat_lookat(Ref(vec3(0, 0, -0.25)), Ref(vec3(0, 0, 0))))
const cm2m = 0.01f0
const mm2m = 0.001f0
const rval = Ref(0.5f0)
const rval2 = Ref(0.5f0)

@kwdef mutable struct RenderState 
    ui_sprite::SK.sprite_t = SK.sprite_t(C_NULL)
    buffer::Vector{Cchar} = zeros(Cchar, 128)
end

const rs = RenderState()
const render_rs() = render(rs)
const render_rs_c = @cfunction(render_rs, Nothing, ())

function render(rs::RenderState) 
    SK.ui_window_begin(u8"Main", Ref(window_pose), vec2(24cm2m, 24cm2m), SK.ui_win_normal, SK.ui_move_face_user)
    SK.ui_button(u8"Testing!")
    SK.ui_sameline()
    SK.ui_input(u8"text", pointer(rs.buffer), sizeof(rs.buffer), vec2(16cm2m, SK.ui_line_height()))
    SK.ui_hslider(u8"slider", rval, 0.0, 1.0, 0.2, 72mm2m, SK.ui_confirm_pinch)
    SK.ui_sameline()
    SK.ui_hslider(u8"slider2", rval2, 0.0, 1.0, 0.0, 72mm2m, SK.ui_confirm_push)
    if SK.input_key(SK.key_mouse_left) & SK.button_state_active > 0
        SK.ui_image(rs.ui_sprite, vec2(6cm2m, 0cm2m))
    end
    if SK.ui_button(u8"Press me!") > 0
        SK.ui_button(u8"DYNAMIC BUTTON!!")
    end
    SK.ui_text(u8"古池や 蛙飛び込む 水の音 - Matsuo Basho", SK.text_align_top_left)
    SK.ui_text(u8"Съешь же ещё этих мягких французских булок да выпей чаю. Широкая электрификация южных губерний даст мощный толчок подъёму сельского хозяйства. В чащах юга жил бы цитрус? Да, но фальшивый экземпляр!", SK.text_align_top_left)
    SK.ui_window_end()
end

function main(rs::RenderState)
    # GC preserve?
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

	rs.ui_sprite = SK.sprite_create_file(u8"StereoKitWide.png", SK.sprite_type_single, u8"default");

    while SK.sk_step(render_rs_c) > 0 end

    SK.sk_shutdown()
end

main(rs)









