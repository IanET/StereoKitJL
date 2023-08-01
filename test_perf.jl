using Printf, IMisc

import LibStereoKit as SK
import LibStereoKit: vec2, vec3, quat, color128, char16_t, bool32_t, ray_t # Base SK types

include("common.jl")

const TARGET_FPS = 29   

const OBJ_POS = vec3(-0.25, 0, -0.5)
const OBJ_ORI = SK.quat_from_angles(22, 90, 22)
const OBJ_SCALE = vec3(0.25, 0.25, 0.35)
const FLOOR_TRANSFORM = Ref(SK.matrix_trs(Ref(vec3(0, -1.5, 0)), Ref(QUAT_IDENTITY), Ref(vec3(30, 0.1, 30))))
const X_RANGE = -0.75:0.01:0.75
const Y_RANGE = -0.75:0.01:0.25
const Z_RANGE = -2.5:0.01:-0.5
const MAX_RATE = 500
const WARMUP_S = 2.5 # run for at least this long before throttling

@kwdef mutable struct FrameStats
    framecount::Int = 0
    frametime::Float64 = time()
    fps::Float32 = 0
    time::Float64 = 0
    bytes::Int64 = 0
    allocs::Int64 = 0
    gctime::Float64 = 0
    avtimems::Float32 = 0
    avbytes::Int = 0
    avallocs::Int = 0
    avgctimems::Float32 = 0
    lastfps::Float32 = 0
end

@kwdef mutable struct RenderState 
    floor_model::SK.model_t = C_NULL
    obj_model::SK.model_t = SK.model_t(C_NULL)
    window_pos::vec3 = vec3(0.0, -0.05, -0.3)
    obj_ang::Float32 = 0
    stats::FrameStats = FrameStats()
    objinfos::Vector{ray_t} = ray_t[]
    rate::Int = MAX_RATE ÷ 2
end

randAngle() = rand() * 360

function addObj(rs::RenderState)
    oi = ray_t(vec3(rand(X_RANGE), rand(Y_RANGE), rand(Z_RANGE)), vec3(randAngle(), randAngle(), randAngle()))
    push!(rs.objinfos, oi)
end

addObj(rs::RenderState, count::Int) = foreach(i -> addObj(rs), 1:count)

function removeLastObj(rs::RenderState)
    if length(rs.objinfos) <= 0; return end
    deleteat!(rs.objinfos, lastindex(rs.objinfos))
end

removeObj(rs::RenderState, count::Int) = foreach(i -> removeLastObj(rs), 1:count)

function updatefps(rs::RenderState)::Void
    fs = rs.stats
    fs.framecount += 1
    delta = time() - fs.frametime
        
    if delta > 1.0
        fs.lastfps = fs.fps
        fs.fps = fs.framecount / delta
        fs.avallocs = fs.allocs ÷ fs.framecount
        fs.avbytes = fs.bytes ÷ fs.framecount
        fs.avgctimems = round((fs.gctime * 1000) / fs.framecount, digits=2)
        fs.avtimems = round((fs.time * 1000) / fs.framecount, digits=2)
        fs.framecount = fs.allocs = fs.bytes = fs.gctime = fs.time = 0

        if fs.fps > TARGET_FPS 
            addObj(rs, rs.rate) 
        elseif fs.fps < TARGET_FPS
            removeObj(rs, rs.rate)
        end

        if fs.fps > TARGET_FPS && fs.lastfps > TARGET_FPS
            rs.rate = (rs.rate * 1.25 |> round |> Int) + 1
        elseif fs.fps < TARGET_FPS * 0.9 && fs.lastfps < TARGET_FPS * 0.9
            rs.rate *= 2
        elseif fs.fps < TARGET_FPS 
            rs.rate ÷= 2
        end
        rs.rate = clamp(rs.rate, 1, MAX_RATE)

        fs.frametime = time()
    end
end

function updatetime(fs::FrameStats, stats)::Void
    fs.time += stats.time
    fs.bytes += stats.bytes
    fs.allocs += stats.gcstats.poolalloc + stats.gcstats.malloc + stats.gcstats.realloc + stats.gcstats.bigalloc
    fs.gctime += stats.gctime
end

col_from_pos(x, y, z) = color128(x-X_RANGE[begin], y-Y_RANGE[begin], z-Z_RANGE[begin], 1.0)
col_from_pos(v::vec3) = col_from_pos(v.x, v.y, v.z)

function render(rs::RenderState)::Void 
    stats = @timed try 
        SK.render_add_model(rs.floor_model, FLOOR_TRANSFORM, COLOR_WHITE, SK.render_layer_0)
        
        head_pose = SK.input_head() |> unsafe_load
        window_pose = Ref(SK.pose_t(rs.window_pos, SK.quat_lookat(Ref(rs.window_pos), Ref(head_pose.position))))
        fps = round(rs.stats.fps; digits=1)
        SK.ui_window_begin("--- Information ---", window_pose, vec2(7cm2m, 2cm2m), SK.ui_win_normal, SK.ui_move_face_user)
        SK.ui_text(
            """
            Objs:        $(length(rs.objinfos))
            FPS:         $fps
            Render:   $(rs.stats.avtimems) ms                  
            Allocs:     $(rs.stats.avallocs)     
            Bytes:      $(rs.stats.avbytes)             
            GC:          $(rs.stats.avgctimems) ms
            """, 
            SK.text_align_center_left) # 14 allocs
        SK.ui_window_end()
        rs.window_pos = window_pose[].position

        rs.obj_ang += 0.2
        if (rs.obj_ang > 360) rs.obj_ang = 0 end

        for objinfo in rs.objinfos
            ori = SK.quat_from_angles(objinfo.dir.x, objinfo.dir.y + rs.obj_ang, objinfo.dir.z)
            m = SK.matrix_trs(Ref(objinfo.pos), Ref(ori), Ref(OBJ_SCALE))
            SK.model_draw(rs.obj_model, m, col_from_pos(objinfo.pos), SK.render_layer_0)
        end

        # instfps = rs.stats.framecount / (time() - rs.stats.frametime) 
        # if (instfps >= TARGET_FPS) addObj(rs) end
        if (fps >= TARGET_FPS) addObj(rs) end
        updatefps(rs)
    catch e
        println("Exception: $e in $(stacktrace(catch_backtrace())[1])")
        sleep(0.5)
    end
    updatetime(rs.stats, stats) 
end

function loadassets(rs::RenderState)::Void
    floor_mesh = SK.mesh_find("default/mesh_cube")
    floor_material = SK.shader_create_file("floor.hlsl") |> SK.material_create
    SK.material_set_transparency(floor_material, SK.transparency_blend)
    rs.floor_model = SK.model_create_mesh(floor_mesh, floor_material)
    
    rs.obj_model = SK.model_create_file("SpaceShuttle.glb", SK.shader_t(C_NULL))
end

async(f::Function, isasync::Bool)::Void = (isasync ? @async(f()) : f())

function main()
    sk_init(app_name = "Test Perf", assets_folder = "C:\\src\\StereoKitJL\\assets", flatscreen_width = 1024, flatscreen_height = 768)
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

