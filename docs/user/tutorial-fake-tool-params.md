# Tutorial: fake-tool PARAMS (Film-PTPECVD01)

Product walkthrough of the **parameter catalog** and **Compare** scope using the
built-in `:fake_tool` seed — no CSV import required.

> Related: [blank → PECVD CSV hand path](tutorial-blank-to-pecvd.md)  
> Recording: `julia --project=. scripts/record_fake_tool_tutorial.jl`

---

## When to use this vs the CSV tutorial

| Path | Use when |
|------|----------|
| **This page (`:fake_tool`)** | You want PARAMS chrome, Compare pins, instant PECVD-like data |
| **CSV hand path** | You want to practice library import / builder / real files |

Same tool id (**Film-PTPECVD01**) and similar parameters; different bootstrap.

---

## Launch

```bash
julia --project=. -e 'using TachikomaTUI; TachikomaTUI.spc_workbench_demo(seed_demos=:fake_tool)'
```

Or from Julia:

```julia
using TachikomaTUI
m = make_fake_tool_workbench()
# app(m)
```

### What you should see

- Tool **Film-PTPECVD01** in the registry / title chrome  
- Side Stats **▸ PARAMS** with three rows, e.g.:
  - Thickness 1.3µm  
  - Refractive Index  
  - HSQ Thickness  
- **One active chart at a time** (param-focused scope `[● Param]`)  
- Synthetic series with intentional OOC/WECO spikes  

---

## Part A — Focus and select parameters

| Key | Action |
|-----|--------|
| **`;`** | Toggle **PARAMS focus** on/off |
| **`j` / `J`** | Next / previous param (**only while focused**) |
| **`↑` / `↓`** | Same as j/J while focused |
| **`1`…`9`** | Jump to param index while focused |
| Esc | Clear PARAMS focus (does not quit while focused) |

**Try:** `;` → `j` → `j` → `J` — active chart should follow the selected parameter.

While **unfocused**, digits **`1`–`8`** still toggle WECO rules (not param jump).

---

## Part B — Compare mode

Multi-param side-by-side is **not** automatic multi-pane for other params. Use:

| Key | Action |
|-----|--------|
| **`,`** | Pin / unpin selected param for Compare (max 3) |
| **`=`** | Toggle **Param** ↔ **Compare** scope |

**Try:**

1. Focus PARAMS (`;`)  
2. Select Refractive Index → **`,`** (pin)  
3. Select HSQ → **`,`** (pin)  
4. Press **`=`** → title chip **`[● Compare]`**  
5. **`=`** again → back to Param scope (pins stay sticky)

**Hazard:** Shift+`,` is chart-cycle `<` — use **unshifted** comma to pin.

---

## Part C — Add chart / library

| Key | Action |
|-----|--------|
| **`+` / `A`** | Add Chart modal (Param vs Analysis) |
| **`m`** | Chart library |
| **`[` `]`** | Cycle within current display set |

Param adds do **not** alone open multi-param panes; Compare does.

---

## Headless capture

```bash
julia --project=. scripts/record_fake_tool_tutorial.jl
# → agent_logs/fake_tool_tutorial.tach
```

```julia
using TachikomaTUI
record_fake_tool_tutorial_demo("agent_logs/fake_tool_tutorial.tach")
```

---

## Open HTML docs from the app

After `julia --project=docs docs/make.jl`: **`h` → `O`** (tutorial index) or  
`julia --project=. scripts/open_docs.jl tutorial`.

---

## Next

- Hand-load real CSVs: [tutorial-blank-to-pecvd.md](tutorial-blank-to-pecvd.md)  
- Operator reference: [workbench.md](workbench.md)  
- Plan: `docs/design/recording-docs-plan.md`  
