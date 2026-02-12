package game

import "core:fmt"
import rl "vendor:raylib"

Rect :: distinct [4]f32

draw_text_ex :: proc(font: rl.Font, text: string, position: [2]f32, spacing: f32, tint: rl.Color, draw := true) -> f32 {
    offset : [2]f32

    for c, _ in text {
        index := rl.GetGlyphIndex(font, c)

        if c == '\n' || c == '\r' do continue
        if c != ' ' && c != '\t' && draw {
            rl.DrawTextCodepoint(font, c, position + offset, f32(font.baseSize) , tint)
        }

        if font.glyphs[index].advanceX == 0 {
            offset.x += f32(font.recs[index].width) + spacing
        }
        else {
            offset.x += f32(font.glyphs[index].advanceX) + spacing
        }
    }
    return offset.x
}

ui_draw_text :: proc(text: string, position: [2]f32, color: rl.Color, font: rl.Font){
    draw_text_ex(font, text, position, f32(1), color)
}

ui_draw_textblock :: proc(text:string, rect: Rect, color: rl.Color, font: rl.Font){

    text := text
    rect := rect

    for len(text) > 0 {
        r := eat_top_rect_ref(&rect, f32(font.baseSize), 0)
        last_space: int

        for ch, i in text {
            end := i == len(text) - 1
            if ch == ' ' || end {
                last_space = i
            }

            if ch == '\n' {
                last_space = i
                break
            }

            size := measure_text(text[:i], font)
            if size.x > r.z && last_space > 0 {
                break
            }
        }

        ui_draw_text(text[:last_space + 1], r.xy, color, font)
        text = text[last_space + 1:]
    }
}

grid_next_rect :: proc(grid_line, grid: ^Rect, width: f32, line_height: f32, spacing :f32 = 20) -> Rect {

    if grid_line.z < width {
        new_line := eat_top_rect_ref(grid, line_height, spacing)
        grid_line ^= new_line
    }

    rect, remainder := eat_left_rect(grid_line^, width, spacing)
    grid_line ^= remainder
    return rect
}

fullscreen_rect :: proc() -> Rect {
    return { 0, 0, f32(rl.GetRenderWidth()), f32(rl.GetRenderHeight())}
}

rect_centre :: proc(rect: Rect) -> [2]f32 {
    return rect.xy + (rect.zw / 2.)
}

centre_rect :: proc(rect: Rect) -> Rect {
    rect := rect
    rect.xy = rect_centre(rect)
    rect.zw = { 0, 0 }
    return rect
}

pad_rect :: proc(rect: Rect, padding: [2]f32) -> Rect {
    rect := rect
    rect.xy += padding
    rect.zw -= padding * 2
    return rect
}

eat_top_rect_ref :: proc(rect: ^Rect, x:f32, spacing: f32) -> Rect {
    eaten, remainder := eat_top_rect(rect^, x, spacing)
    rect ^= remainder
    return eaten
}

eat_left_rect_ref :: proc(rect: ^Rect, x: f32, spacing: f32) -> Rect {
    eaten, remainder := eat_left_rect(rect^, x, spacing)
    rect ^= remainder
    return eaten
}

eat_left_rect :: proc(rect: Rect, x: f32, spacing: f32) -> (eaten: Rect, remainder: Rect){
    eaten = {rect.x, rect.y, x, rect.w }
    remainder = rect
    remainder.x += x + spacing
    remainder.z -= x + spacing
    return
}

eat_top_rect :: proc(rect: Rect, y: f32, spacing: f32) -> (eaten: Rect, remainder: Rect){
    eaten = {rect.x, rect.y, rect.z, y }
    remainder = rect
    remainder.y += y + spacing
    remainder.w -= y + spacing
    return
}

eat_bottom_rect :: proc(rect: Rect, y: f32, spacing: f32) -> (eaten: Rect, remainder: Rect){
    remainder = rect
    remainder.w -= (y + spacing)
    eaten = { rect.x, rect.y + rect.w - y, rect.z, y }
    return
}

eat_bottom_rect_ref :: proc(rect: ^Rect, y: f32, spacing: f32) -> Rect {
    eaten, remainder := eat_bottom_rect(rect^, y, spacing)
    rect ^= remainder
    return eaten
}

eat_right_rect :: proc(rect: Rect, x: f32, spacing: f32) -> (eaten: Rect, remainder: Rect){
    remainder = rect
    remainder.z -= (x + spacing)
    eaten = { rect.x + rect.z - x, rect.y, x, rect.w }
    return
}

eat_right_rect_ref :: proc(rect: ^Rect, x: f32, spacing: f32) -> Rect {
    eaten, remainder := eat_right_rect(rect^, x, spacing)
    rect ^= remainder
    return eaten
}

measure_text :: proc(text: string, font: rl.Font) -> [2]f32 {
    width := draw_text_ex(font, text, {}, f32(1), {}, draw = false)
    return { width, f32(font.baseSize) }
}