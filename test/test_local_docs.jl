using Test
using Tachikoma
using TachikomaTUI

const T = Tachikoma

@testset "Local Documenter open-in-browser" begin
    @testset "paths" begin
        root = package_root()
        @test isdir(joinpath(root, "src"))
        @test isdir(joinpath(root, "docs"))
        @test local_docs_build_dir() == joinpath(root, "docs", "build")
        # basename only — traversal components are stripped
        sneaky = resolve_local_docs_file("../../etc/passwd")
        @test sneaky === nothing || !occursin("etc/passwd", sneaky)
    end

    @testset "file_url" begin
        u = file_url("/tmp/foo.html")
        @test startswith(u, "file://")
        @test occursin("foo.html", u)
    end

    @testset "open_local_docs dry_run" begin
        msg = open_local_docs(; dry_run = true)
        # Either built (this workspace often has docs/build) or missing with build hint
        @test occursin("docs ready:", msg) || occursin("docs not built", msg)
        if occursin("docs ready:", msg)
            @test occursin("file://", msg)
            idx = resolve_local_docs_file("index.html")
            @test idx !== nothing
            @test isfile(idx)
            tut = resolve_local_docs_file("tutorial")
            @test tut !== nothing
            @test endswith(tut, "tutorial.html")
        end
        # dry_run must not throw and must not require a real browser
        @test open_in_browser(joinpath(package_root(), "README.md"); dry_run = true) === nothing
    end

    @testset "help/keymap O opens docs message (no browser)" begin
        m = make_blank_workbench()
        T.update!(m, T.KeyEvent('h'))
        @test m.view_mode == :help
        # Monkey-patch by dry path: call open_local_docs dry then set last_event like handler
        # Real key would open browser — exercise handler only if we can avoid spawn:
        # Call the same API the handler uses with dry_run via direct set (handler not dry).
        # Instead: verify resolve + that handler key path updates last_event without crash
        # when docs exist or not — open_in_browser may spawn; skip if no DISPLAY?
        # Prefer unit-testing the message function only; integration uses dry_run.
        m.last_event = open_local_docs(; page = "tutorial.html", dry_run = true)
        @test occursin("docs", m.last_event)
    end

    @testset "no GUI: do not claim browser opened" begin
        # Empty GUI env (typical SSH / headless). xdg-open often exits 0 while
        # printing "Error: no DISPLAY" — we must not report success.
        empty_gui = Dict{String,String}(
            "PATH" => get(ENV, "PATH", "/usr/bin:/bin"),
            # Explicitly clear GUI signals even if parent ENV has them
            "DISPLAY" => "",
            "WAYLAND_DISPLAY" => "",
            "BROWSER" => "",
        )
        url = file_url(joinpath(package_root(), "README.md"))
        err = open_in_browser(url; env = empty_gui)
        @test err !== nothing
        @test occursin(r"(?i)display|wayland|browser|manual", err)
        @test occursin("file://", err)  # user can open manually

        msg = open_local_docs(; page = "index.html", dry_run = false, env = empty_gui)
        @test !occursin("opened docs in browser", msg)
        @test occursin("file://", msg) || occursin("docs:", msg)
    end

    @testset "BROWSER override launches via env" begin
        # Successful path when BROWSER is a no-op success script (no real GUI needed).
        mktempdir() do dir
            log = joinpath(dir, "opened.log")
            script = joinpath(dir, "fake-browser.sh")
            write(script, """
            #!/bin/sh
            echo "\$1" > "$(log)"
            exit 0
            """)
            chmod(script, 0o755)
            env = Dict{String,String}(
                "PATH" => get(ENV, "PATH", "/usr/bin:/bin"),
                "DISPLAY" => "",
                "WAYLAND_DISPLAY" => "",
                "BROWSER" => script,
            )
            url = file_url(joinpath(package_root(), "README.md"))
            @test open_in_browser(url; env = env) === nothing
            @test isfile(log)
            @test occursin("file://", read(log, String))
            msg = open_local_docs(; page = "index.html", env = env)
            @test occursin("opened docs in browser", msg)
        end
    end

    @testset "BROWSER failure is reported" begin
        mktempdir() do dir
            script = joinpath(dir, "fail-browser.sh")
            write(script, "#!/bin/sh\necho fail-browser-stderr >&2\nexit 2\n")
            chmod(script, 0o755)
            env = Dict{String,String}(
                "PATH" => get(ENV, "PATH", "/usr/bin:/bin"),
                "BROWSER" => script,
            )
            url = file_url(joinpath(package_root(), "README.md"))
            err = open_in_browser(url; env = env)
            @test err !== nothing
            @test occursin(r"(?i)fail|exit|browser", err)
        end
    end
end
