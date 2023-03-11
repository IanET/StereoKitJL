import LibStereoKit as SK
import LibStereoKit: vec2, vec3, quat, color128, char16_t, bool32_t # Base SK types
using Printf, IMisc

# --- Helpers ---

const cm2m = 0.01f0
const mm2m = 0.001f0

Base.:(*)(a::vec3, b::vec3)::vec3 = vec3(a.x*b.x, a.y*b.y, a.z*b.z)
Base.:(+)(a::vec3, b::vec3)::vec3 = vec3(a.x+b.x, a.y+b.y, a.z+b.z)
vec3() = vec3(0, 0, 0)
vec3(v) = vec3(v, v, v)

function sk_renderloop(render::Function)::Void
    render_wrapper() = try render() catch end # Eat exceptions
    render_wrapper_c = @cfunction($render_wrapper, Void, ()) # Not supported on all cpu architectures
    if isinteractive()
        while SK.sk_step(render_wrapper_c) > 0; sleep(0.01) end
    else
        while SK.sk_step(render_wrapper_c) > 0; end
    end
end

function sk_init(;
    app_name::String = "",
    assets_folder::String = "",
    display_preference::SK.display_mode_ = SK.display_mode_mixedreality,
    blend_preference::SK.display_blend_ = SK.display_blend_any_transparent,
    no_flatscreen_fallback::Bool = false,
    depth_mode::SK.depth_mode_ = SK.depth_mode_balanced,
    log_filter::SK.log_ = SK.log_diagnostic,
    overlay_app::Bool = false,
    overlay_priority::Int = 0, 
    flatscreen_pos_x::Int = 0,
    flatscreen_pos_y::Int = 0, 
    flatscreen_width::Int = 0, 
    flatscreen_height::Int = 0, 
    disable_flatscreen_mr_sim::Bool = false,
    disable_unfocused_sleep::Bool = false)

    GC.@preserve app_name assets_folder begin 
        settings = SK.sk_settings_t(
            pointer(app_name),
            pointer(assets_folder),
            display_preference,
            blend_preference,
            no_flatscreen_fallback |> bool32_t,
            depth_mode,
            log_filter,
            overlay_app,
            overlay_priority |> UInt32,
            flatscreen_pos_x |> Int32,
            flatscreen_pos_y |> Int32,
            flatscreen_width |> Int32,
            flatscreen_height |> Int32,
            disable_flatscreen_mr_sim |> bool32_t,
            disable_unfocused_sleep |> bool32_t,
            C_NULL, 
            C_NULL
        )
        SK.sk_init(settings)
    end
end

# --- App ---

const white = color128(1, 1, 1, 1)
const black = color128(0, 0, 0, 1)
const gray = color128(0.5, 0.5, 0.5, 1)
const transparent_black = color128(0, 0, 0, 0)
const blueish = color128(0.5, 0.6, 0.7, 1.0)
const quat_identity = SK.quat(0, 0, 0, 1)
const floor_transform = Ref(SK.matrix_trs(Ref(vec3(0, -1.5, 0)), Ref(quat_identity), Ref(vec3(30, 0.1, 30))))
const ROT_ANG_DELTA = 0.25

@kwdef mutable struct FrameStats
    framecount::Int = 0
    frametime::Float64 = time()
    fps::Float32 = 0
    time::Float64 = 0
    bytes::Int64 = 0
    allocs::Int64 = 0
    gctime::Float64 = 0
    avtimems::Int = 0
    avbytes::Int = 0
    avallocs::Int = 0
    avgctimems::Int = 0
end

@kwdef mutable struct RenderState 
    floor_model::SK.model_t = C_NULL
    obj_model::SK.model_t = C_NULL
    window_pos::vec3 = vec3(0.0, -0.05, -0.3)
    obj_pry::vec3 = vec3()
    stats::FrameStats = FrameStats()
end

function updatefps(fs::FrameStats)::Void
    fs.framecount += 1
    delta = time() - fs.frametime
    if delta >= 1.0
        fs.fps = fs.framecount / delta
        fs.avallocs = fs.allocs ÷ fs.framecount
        fs.avbytes = fs.bytes ÷ fs.framecount
        fs.avgctimems = (fs.gctime * 1000) ÷ fs.framecount
        fs.avtimems = (fs.time * 1000) ÷ fs.framecount
        fs.framecount = fs.allocs = fs.bytes = fs.gctime = fs.time = 0
        fs.frametime = time()
    end
end

function updatetime(fs::FrameStats, stats)::Void
    fs.time += stats.time
    fs.bytes += stats.bytes
    fs.allocs += stats.gcstats.poolalloc + stats.gcstats.malloc + stats.gcstats.realloc + stats.gcstats.bigalloc
    fs.gctime += stats.gctime
end

function rotateObj(rs::RenderState)::Void
    rot(r) = (r += ROT_ANG_DELTA; r > 360 ? r -= 360 : r)
    (;x, y, z) = rs.obj_pry
    rs.obj_pry = vec3(rot(x), rot(y), z)
end

function hslToRgb(h::Float32, s::Float32, l::Float32)::Tuple{Float32, Float32, Float32}
    @assert h >= 0 && h <= 1.0
    @assert s >= 0 && s <= 1.0
    @assert l >= 0 && l <= 1.0

    function hue2rgb(p, q, t)::Float32
        if (t < 0) t += 1 end
        if (t > 1) t -= 1 end
        if (t < 1/6) return p + (q - p) * 6 * t end
        if (t < 1/2) return q end
        if (t < 2/3) return p + (q - p) * (2/3 - t) * 6 end
        return p
    end

    local r::Float32
    local g::Float32 
    local b::Float32
    
    if s == 0
        r = g = b = l
    else
        q = l < 0.5 ? l * (s + 1) : (l + s) - (l * s)
        p = (2 * l) - q
        r = hue2rgb(p, q, h + 1/3)
        g = hue2rgb(p, q, h)
        b = hue2rgb(p, q, h - 1/3)
    end
    
    return (r, g, b)
end

function prToCol(p::Float32, r::Float32)::color128
    t = (p + r) / 720f0
    (r, g, b) = hslToRgb(t, 0.75f0, 0.5f0) # easier to do color cylcing with hsl
    return color128(r, g, b, 1.0) 
end

quat(v::vec3) = SK.quat_from_angles(v.x, v.y, v.z)

function render(rs::RenderState)::Void 
    stats = @timed try 
        # SK.render_add_model(rs.floor_model, floor_transform, white, SK.render_layer_0)
        
        head_pose = SK.input_head() |> unsafe_load
        window_pose = Ref(SK.pose_t(rs.window_pos, SK.quat_lookat(Ref(rs.window_pos), Ref(head_pose.position))))
        
        # Per sec avg
        fps = round(rs.stats.fps; digits=1)
        SK.ui_window_begin("--- Information ---", window_pose, vec2(7cm2m, 2cm2m), SK.ui_win_normal, SK.ui_move_face_user)
        SK.ui_push_text_style
        SK.ui_text(
            """
            FPS:         $fps
            Render:   $(rs.stats.avtimems) ms                  
            Allocs:     $(rs.stats.avallocs)     
            Bytes:      $(rs.stats.avbytes)             
            GC:          $(rs.stats.avgctimems) ms
            """, 
            SK.text_align_center_left) # 14 allocs
        SK.ui_window_end()
        rs.window_pos = window_pose[].position

        rotateObj(rs)
        col = prToCol(rs.obj_pry.x, rs.obj_pry.y)
        m = SK.matrix_trs(vec3(0, 0, -1.0) |> Ref, quat(rs.obj_pry) |> Ref, vec3(2.5) |> Ref) # pos, orientation, scale
        SK.model_draw(rs.obj_model, m, col, SK.render_layer_0)

        updatefps(rs.stats)
    catch e
        println("Exception: $e in $(stacktrace(catch_backtrace())[1])")
        sleep(0.5)
    end
    updatetime(rs.stats, stats) 
end

function loadassets(rs::RenderState)::Void
    material = SK.material_find("default/material")
    mesh = SK.mesh_gen_cube(vec3(0.25, 0.25, 0.25), 4)
    rs.obj_model = SK.model_create_mesh(mesh, material)

    SK.render_enable_skytex(false)
    SK.input_hand_visible(SK.handed_left, false)
    SK.input_hand_visible(SK.handed_right, false)
end

async(f::Function, isasync::Bool)::Void = (isasync ? @async(f()) : f())

function main()
    sk_init(app_name = "Cube", assets_folder = "assets")
    rs = RenderState()
    loadassets(rs)

    # Async if in vscode, sync otherwise
    async(isinteractive()) do
        sk_renderloop(() -> render(rs))
        # ... cleanup assets ...
        SK.sk_shutdown()
    end
end

main()
