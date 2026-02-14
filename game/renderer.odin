package game
import rl "vendor:raylib"
import "core:math"

Circle :: struct {
    centre: [2]f32,
    radius: f32,
}
Rectangle :: distinct [4]f32

DrawTexture :: struct {
    position: [2]f32,
    type: TextureType,
    frame: int,
    scale: f32,
    rotation: f32
}

DrawCircle :: struct {
    circle: Circle,
    scale: f32,
    fill, line: rl.Color
}

DrawRect :: struct {
    rect: Rectangle,
    fill, line: rl.Color
}

DrawCommand :: union {
    DrawCircle, DrawRect, DrawTexture
}


Layer :: enum {
    Low, Middle, High, UI
}

draw_circle :: proc(layer: Layer, circle: Circle, fill, line: rl.Color, scale: f32){
    command: DrawCommand = DrawCircle {circle, scale, fill, line }
    append(&state.draw_commands[layer], command)
}

draw_rect :: proc(layer: Layer, rect: Rectangle, fill, line: rl.Color){
    command: DrawCommand = DrawRect {rect, fill, line }
    append(&state.draw_commands[layer], command)
}

draw_texture :: proc(layer: Layer,
    type: TextureType,
    position: [2]f32,
    scale :f32 = 1.0,
    rotation: f32 = 0,
    frame: int = 0){
    command: DrawCommand = DrawTexture {position, type, frame, scale, rotation}
    append(&state.draw_commands[layer], command)
}

render :: proc(commands: ^[Layer][dynamic]DrawCommand){

    @static mode: int = 0
    if rl.IsKeyPressed(.F) {
        mode += 1
        mode %= 3
    }

    shader := state.shaders[.Pixel].shader
    {
        mode_names := []string{"klems", "iq", "none"}
        log(mode_names[mode])
        rl.SetShaderValue(shader, 1, &mode, .INT)
    }
    rl.BeginBlendMode(.ALPHA_PREMULTIPLY)
    defer rl.EndBlendMode()
    rl.BeginShaderMode(shader)
    defer rl.EndShaderMode()


    for &layer_commands in commands {
        for &command in layer_commands {
            switch &v in command {
            case DrawCircle:
                rl.DrawCircleV(v.circle.centre, v.circle.radius * v.scale, v.fill)
            case DrawRect:
                rl.DrawRectangleRec(transmute(rl.Rectangle)v.rect, v.fill)
            case DrawTexture:
                texture :=  state.textures[v.type]
                frames :=   state.frames[v.type]
                cel_size := [2]f32 { f32((int(texture.width) / frames) + 1), f32(texture.height) }

                src := rl.Rectangle { cel_size.x * f32(v.frame), 0, cel_size.x, cel_size.y }
                dst := rl.Rectangle { v.position.x, v.position.y, cel_size.x * v.scale, cel_size.y * v.scale }

                rotation := math.to_degrees(v.rotation)

                rl.DrawTexturePro(texture, src, dst, cel_size / 2, rotation, rl.WHITE)
            }
        }
        clear(&layer_commands)
    }
}