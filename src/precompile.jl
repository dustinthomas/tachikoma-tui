# PrecompileTools workload for SPC workbench hot paths.
# Prefer no new runtime behavior — only construct / resolve / view / serialize.
using PrecompileTools: @setup_workload, @compile_workload

@setup_workload begin
    @compile_workload begin
        d = generate_spc_workbench_data(20; seed = 1)
        m = SPCWorkbenchModel(data = d, paused = true)
        _ensure_charts!(m)
        ch = current_chart(m)
        resolve_chart_render_context(ch)
        # schema-v1 serialize (no file I/O)
        workbench_to_dict(m)
        # TestBackend view path (Tachikoma already a runtime dep)
        tb = TestBackend(60, 18)
        reset!(tb.buf)
        view(m, Frame(tb.buf, Rect(1, 1, tb.width, tb.height), [], []))
    end
end
