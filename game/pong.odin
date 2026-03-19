package game

import rl "vendor:raylib"
import "core:fmt"
import "core:math/linalg"

Pong :: struct {
    initialized: bool,
    paddles: [2]Rect,
    ball: Rect,
    ball_velocity: [2]f32,
    scores: [2]int,
}

run_pong :: proc(pong: ^Pong, rect: Rect, delta: f32){
    draw_rect(.UI, rect, rl.BLACK, rl.BLACK)

        if !pong.initialized {
            for &paddle in pong.paddles {
            paddle.zw = { 10, 100 }
        }

        pong.ball.zw = 10
        pong.ball.xy = (rect.zw - pong.ball.zw) / 2
        pong.ball_velocity = { -200, 400 }
        pong.scores = {}
        pong.paddles[0].xy = { 50, 200 }
        pong.paddles[1].xy = { rect.z - 50, 200 }
        pong.initialized = true
    }
    if rl.IsKeyPressed(.N) do pong.initialized = false


    // update
    player_direction := f32(int(rl.IsKeyDown(.S)) - int(rl.IsKeyDown(.W)))
    pong.paddles[0].y += player_direction * delta * 500

    player_direction_2 := f32(int(rl.IsKeyDown(.DOWN)) - int(rl.IsKeyDown(.UP)))
    pong.paddles[1].y += player_direction_2 * delta * 500

    // ball
    pong.ball.xy += pong.ball_velocity * delta
    if pong.ball.y > rect.w - pong.ball.w || pong.ball.y < 0 {
        pong.ball_velocity.y *= -1
    }

    prev_scores := pong.scores
    if pong.ball.x > rect.z - pong.ball.z do pong.scores[0] += 1
    if pong.ball.x < 0 do pong.scores[1] += 1
    if prev_scores != pong.scores do pong.ball.xy = (rect.zw - pong.ball.zw) / 2

    for paddle in pong.paddles {
        if !rect_overlaps(pong.ball, paddle) do continue
        pong.ball_velocity.x *= -1
    }

    // paddles
    for &paddle in pong.paddles {
        paddle.y = clamp(paddle.y, 0, rect.w - paddle.w)
    }

    pong.ball.xy = linalg.clamp(pong.ball.xy, [2]f32{}, rect.zw - pong.ball.zw)

    for paddle in pong.paddles {
        draw_rect(.UI, paddle + { rect.x, rect.y, 0, 0 }, rl.WHITE, rl.WHITE)
    }
    draw_rect(.UI, pong.ball + { rect.x, rect.y, 0, 0 }, rl.WHITE, rl.WHITE)

    // overlay
    overlay := rect

    // dotted line
    if true {
        middle := pad_rect(centre_rect(overlay), {-4, -overlay.w / 2})
        padding: f32 = 10
        SEGMENTS :: 20
        segment_size: f32 = (middle.w - padding * SEGMENTS) / SEGMENTS
        for i in 0..<SEGMENTS {
            segment := eat_top_rect_ref(&middle, segment_size, padding)
            draw_rect(.UI,segment, rl.WHITE, rl.WHITE)
        }
    }

    // scores
    half_width := overlay.z / 2
    for score, i in pong.scores {
        side := eat_left_rect_ref(&overlay, half_width, 0)
        top := eat_top_rect_ref(&side, 40, 10)
        draw_text(.UI, fmt.tprintf("{}", score), top, rl.WHITE, scale = 2)
    }
}