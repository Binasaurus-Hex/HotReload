package main

import "core:fmt"
import "core:time"
import "core:strings"
import "core:dynlib"
import "core:os"
import "core:os/os2"
import path "core:path/filepath"

GameAPI :: struct {
    init_window: proc() -> rawptr,
    set_window_state: proc(rawptr),
    run: proc(bool, string) -> bool,
    save: proc() -> []u8,
    load: proc(state: []u8),

    _game_api_handle: dynlib.Library
}

Backend :: enum {
    Raylib, Karl2D
}

BACKEND :: Backend.Raylib

get_api_path :: proc(version: int) -> string {
    return fmt.tprintf("game_{}.dll", version)
}

build_api :: proc(version: int) -> (output_path: string, error_string: string, success: bool) {

    start := time.now()
    defer {
        fmt.printfln("build took : {}s", time.duration_seconds(time.since(start)))
    }

    output_path = get_api_path(version)
    output := fmt.tprint("-out=", output_path)

    game_folder := "game" if BACKEND == .Raylib else "game_karl2d"

    odin_path := path.join({ODIN_ROOT, "odin"}, context.temp_allocator)

    process_description := os2.Process_Desc {
        command = {
            odin_path,
            "build",
            game_folder,
            "-o=none",
            "-linker=radlink",
            "-build-mode=dll",
            "-define:RAYLIB_SHARED=true" if BACKEND == .Raylib else "",
            "-extra-linker-flags=/NOEXP /NOIMPLIB",
            output
            }
    }

    state, std_out, std_err, err := os2.process_exec(process_description, context.temp_allocator)
    assert(err == nil)
    error_string = string(std_err)

    fmt.println(error_string)

    return output_path, error_string, state.exit_code == 0
}

main :: proc(){

    assert(ODIN_OS == .Windows, "Only tested on windows, remove this if you want to go fix it for your OS")

    apis: [dynamic]GameAPI
    api_version: int
    started: bool
    state: []u8
    api: GameAPI

    if BACKEND == .Raylib {
        raylib_dll := path.join({ODIN_ROOT, "vendor", "raylib", "windows", "raylib.dll"}, context.temp_allocator)
        copy_err := os2.copy_file("raylib.dll", raylib_dll)
        assert(copy_err == nil)
    }

    window_state: rawptr

    for {

        dll_path, error_string, success := build_api(api_version)
        if success {
            api = {}
            count, ok := dynlib.initialize_symbols(&api, dll_path, "", "_game_api_handle")
            append(&apis, api)
            api_version += 1
        }
        else if !started {
            break
        }


        if started {
            api.set_window_state(window_state)
            api.load(state)
        }

        if !started {
            window_state = api.init_window()
            started = true
        }

        reload := api.run(!success, error_string)

        if reload do state = api.save()

        free_all(context.temp_allocator)

        if !reload do break
    }

    for api, i in apis {
        if !dynlib.unload_library(api._game_api_handle) {
            fmt.printfln("Failed unloading lib: {0}", dynlib.last_error())
        }

        {
            dll := fmt.tprintf("game_{}.dll", i)
            err: os2.Error
            err = os2.remove(dll)
        }

        {
            pdb := fmt.tprintf("game_{}.pdb", i)
            err: os2.Error
            err = os2.remove(pdb)
        }
        {
            rdi := fmt.tprintf("game_{}.rdi", i)
            err: os2.Error
            err = os2.remove(rdi)
        }
    }
}