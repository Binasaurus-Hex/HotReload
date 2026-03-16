package game

import rl "vendor:raylib"
import "core:time"
import "core:strings"
// import os "core:os/os2"
import sa "core:container/small_array"
import "core:c"
import "core:fmt"

UniformValue :: union {
    f32, i32, [2]f32, [2]i32, [][2]f32, []i32, rl.Texture, [4]f32, [3]f32, [][4]f32
}

ShaderInterface :: struct {
    shader: rl.Shader,
    uniforms: map[string] UniformValue `fs:"-"`,
    uniform_locs: map[string] c.int `fs:"-"`,
}

load_shader :: proc(vertex: string, fragment: string) -> ShaderInterface {

    vertex_c := strings.clone_to_cstring(vertex, context.temp_allocator)
    fragment_c := strings.clone_to_cstring(fragment, context.temp_allocator)

    interface := ShaderInterface {
        shader = rl.LoadShader(vertex_c, fragment_c),
    }
    return interface
}

unload_shader :: proc(shader: ^ShaderInterface){
    rl.UnloadShader(shader.shader)
}

interface_set_uniforms :: proc(interface: ^ShaderInterface){
    for key, &value in interface.uniforms {


        location, found := interface.uniform_locs[key]
        if !found {
            cstring_key := strings.clone_to_cstring(key, context.temp_allocator)
            location = rl.GetShaderLocation(interface.shader, cstring_key)
            interface.uniform_locs[key] = location
        }

        switch &v in value {
            case i32:
                rl.SetShaderValue(interface.shader, location, &v, .INT)
            case f32:
                rl.SetShaderValue(interface.shader, location, &v, .FLOAT)
            case [2]f32:
                rl.SetShaderValue(interface.shader, location, &v, .VEC2)
            case [2]i32:
                rl.SetShaderValue(interface.shader, location, &v, .IVEC2)
            case [3]f32:
                rl.SetShaderValue(interface.shader, location, &v, .VEC3)
            case [4]f32:
                rl.SetShaderValue(interface.shader, location, &v, .VEC4)

            case []i32:
                count := i32(len(v))
                count_key := fmt.ctprintf("%s_count", key)
                count_loc := rl.GetShaderLocation(interface.shader, count_key)
                rl.SetShaderValueV(interface.shader, location, &v[0], .INT, count)
                rl.SetShaderValue(interface.shader, count_loc, &count, .INT)
            case [][2]f32:
                count := i32(len(v))
                count_key := fmt.ctprintf("%s_count", key)
                count_loc := rl.GetShaderLocation(interface.shader, count_key)
                rl.SetShaderValueV(interface.shader, location, &v[0], .VEC2, count)
                rl.SetShaderValue(interface.shader, count_loc, &count, .INT)
            case [][4]f32:
                count := i32(len(v))
                count_key := fmt.ctprintf("%s_count", key)
                count_loc := rl.GetShaderLocation(interface.shader, count_key)
                rl.SetShaderValueV(interface.shader, location, &v[0], .VEC4, count)
                rl.SetShaderValue(interface.shader, count_loc, &count, .INT)

            case rl.Texture:
                rl.SetShaderValueTexture(interface.shader, location, v)

        }
    }
}

@(deferred_none=rl.EndShaderMode)
with_shader :: proc(interface: ^ShaderInterface) -> bool {
    rl.BeginShaderMode(interface.shader)
    interface_set_uniforms(interface)
    return true
}