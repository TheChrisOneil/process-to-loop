# Architecture: the 4+1 views

Kruchten's 4+1 model, applied to `process-to-loop`. Written 2026-10-09.

Every diagram below is also rendered beside this file, so it can be read without a toolchain:
`logical.svg`, `process-L1.svg`, `process-L2.svg`, `development.svg`, `physical.svg`,
`scenario-L1-scripts.svg`, `scenario-L2-tick.svg`. All seven are verified to render — a diagram
that does not compile is a diagram nobody checked.

Five views, each answering a different stakeholder's question:

| view | answers | for |
|---|---|---|
| **Logical** | what are the things, and how do they relate | the design owner |
| **Process** | what runs, when, and what blocks what | the operator |
| **Development** | what is the code organised into | whoever maintains it |
| **Physical** | what is deployed where | whoever stands it up |
| **+1 Scenarios** | what actually happens, script by script | all of them |

**The distinction this architecture turns on** is the one in
`loop-engineering-in-a-regulated-space.md`: **L1**, the design loop, is a development tool. **L2**,
the emitted bundle, is the regulated artifact. L1's entire job is to make L2 provable. Every view
below marks which one it is describing.

---

## 1. Logical view — the artifacts and what binds them

What exists, and which binding holds each pair together. Every edge labelled `sha256` is a
content binding, not a filename reference: change the content and the binding breaks.

```mermaid
classDiagram
    class UseCase {
        +prose text
        +sha256
    }
    class QuestionSet {
        +Q1..Qn
        +class: structural|parametric
        +answer: stated|unanswered|delegated
        +provenance: real|synthetic
        +use_case_sha256
    }
    class Catalog {
        +owner
        +phi_may_reach_models
        +phi_model_review_by
    }
    class Tool {
        +provides
        +data_class
        +may_not
        +review_by
    }
    class Skill {
        +covers
        +applies_to
        +owner
        +review_by
    }
    class Design {
        +meta.approver
        +meta.questions_sha256
        +meta.method_sha256
        +unit, steps, gates
        +sources, tools, skills
        +decisions, evidence, record, kpis
    }
    class DecisionTable {
        +hit: unique|first
        +inputs, outputs
        +rules
    }
    class Verdict {
        +author_model
        +audit_model
        +subject_sha256
        +defects[]
    }
    class Acceptance {
        +design_sha256
        +signer
        +chain
    }
    class Bundle {
        +run.sh
        +steps/
        +checks/
        +ledger
    }

    UseCase "1" --> "1" QuestionSet : use_case_sha256
    QuestionSet "1" --> "1" Design : questions_sha256
    Catalog "1" *-- "n" Tool
    Catalog "1" *-- "n" Skill
    Tool "n" <-- "n" Design : names, narrows
    Skill "n" <-- "n" Design : applies, never gates on
    Design "1" *-- "n" DecisionTable
    Design "1" <-- "1" Verdict : subject_sha256
    Design "1" <-- "1" Acceptance : design_sha256 + signer == meta.approver
    Acceptance "1" --> "1" Bundle : compiled only after
    DecisionTable "n" --> "n" Bundle : emitted as TSV + evaluator
```

**The rule this view encodes:** nothing downstream refers to anything upstream by *name*. Every
binding is a digest, so a change anywhere breaks the chain visibly rather than silently.

---

## 2. Process view — what runs and what blocks

**L1.** Seventeen steps, seven of them gates, two held by a person. Swimlanes are who executes.

```mermaid
stateDiagram-v2
    direction TB
    [*] --> bind_checks

    state "DETERMINISTIC (code)" as det1 {
        bind_checks : bind-checks · values bound once, at cook time
        archive_prior : archive-prior · last run beyond reach
        bind_checks --> archive_prior
    }
    det1 --> intake

    state "MODEL (author provider)" as m1 {
        intake : intake · read and screen the description
        questions : questions · ask what it does not say
        intake --> questions
    }
    m1 --> answers

    state "PERSON" as p1 {
        answers : answers · stated | unanswered | delegated
    }
    p1 --> answered

    answered : GATE answered · every block has an answer
    answered --> author

    state "THE LOOP (max 5 attempts)" as loop {
        author : author-design · write it
        validate_i : validate 45 rules
        audit_i : audit on a DIFFERENT provider
        classify : classify by_revision | needs_a_person
        author --> validate_i
        validate_i --> audit_i : passes form
        validate_i --> author : fails form
        audit_i --> classify
        classify --> author : a revision can fix it
        classify --> [*] : only a person can
    }
    loop --> validate_g

    validate_g : GATE validate · the design passes its rules
    validate_g --> audited
    audited : GATE audited · real, different model, THIS design
    audited --> render
    render : render · diagrams and the brief
    render --> diagrams
    diagrams : GATE diagrams · the views carry every control
    diagrams --> findings
    findings : findings · what is left for a person
    findings --> accept

    state "PERSON" as p2 {
        accept : accept-design · signs the SHA-256
    }
    accept --> compile
    compile : compile · formula, checks, bundle
    compile --> records
    records : GATE records · runs a tick, reads the ledger
    records --> [*]
```

**L2.** One tick of the emitted bundle. Batch steps once, unit steps per unit.

```mermaid
stateDiagram-v2
    direction LR
    [*] --> batch
    state batch {
        direction TB
        reads : read each @source through its @tool
        reads --> logged : ledger row per read, with its permission
        logged --> batch_gate
        batch_gate : batch gates
        batch_gate --> units : permit
        batch_gate --> stop : REFUSE whole run
    }
    units --> per_unit
    state per_unit {
        direction TB
        work : mechanical steps
        work --> judge
        judge : thinking step · skill rows logged IN FORCE
        judge --> test
        test : test step recomputes the claim
        test --> gate
        gate : unit gate
        gate --> record : permit
        gate --> refuse : REFUSE this unit only
    }
    per_unit --> [*]
    stop --> [*]
    refuse --> [*]
```

**The exit-code contract, which both levels honour:**

| | |
|---|---|
| `0` | the condition does not hold; work continues |
| `1` | refused — a business outcome, and the refusal names the next human action |
| `75` | could not run — infrastructure. **Never** a business failure, and costs no attempt |

---

## 3. Development view — how the code is organised

```mermaid
flowchart TB
    subgraph parsers["lib/ — parsers, one per format"]
        parse["parse.awk<br/>the design"]
        qawk["questions.awk<br/>the question set"]
        cawk["catalog.awk<br/>tools and skills"]
        dtcell["dt-cell.awk<br/>what a CELL means"]
    end

    subgraph rules["lib/ — rules, read after a parser"]
        vawk["validate.awk<br/>V1..V45"]
        qrules["questions-rules.awk<br/>I1..I8, A1..A7"]
        vfawk["validate-formula.awk<br/>F1..F17"]
    end

    subgraph emit["lib/ — emitters, deterministic"]
        eform["emit-formula.awk"]
        echeck["emit-check.awk"]
        edec["emit-decision.awk"]
        rseq["render-seq.awk"]
        rflow["render-flow.awk"]
    end

    subgraph entry["tooling/ — one job each"]
        vsh["validate.sh"]
        qsh["questions.sh"]
        csh["compile.sh"]
        esh["emit-bundle.sh"]
        bsh["brief.sh"]
        dsh["decide.sh"]
        ash["accept.sh"]
        aush["audit-design.sh"]
    end

    subgraph gates["checks/ — one job each, exit 0/1/75"]
        cb["checks-bound.sh"]
        dr["design-reviewed.sh"]
        dv["design-validate.sh"]
        da["design-audited.sh"]
        qa["questions-asked.sh"]
        qan["questions-answered.sh"]
        br["bundle-records.sh"]
    end

    parse --> vawk
    dtcell --> vawk
    qawk --> qrules
    cawk -.->|flattened| vawk
    parse --> emit
    dtcell --> edec

    vawk --> vsh
    qrules --> qsh
    emit --> csh
    emit --> esh
    emit --> bsh
    dtcell --> dsh

    vsh --> dv
    vsh --> dr
    aush --> dr
    qsh --> qa
    qsh --> qan
    esh -.->|runs one tick| br

    classDef shared fill:#fef3c7,stroke:#b45309
    class dtcell,parse,cawk,qawk shared
```

**The constraint this view exists to show:** `dt-cell.awk` is loaded by the validator **and**
copied into every emitted bundle. One definition of what a cell means. Two copies would be two
dialects of the same table, and the first divergence would sit between the rules that passed a
design and the check that enforces it.

---

## 4. Physical view — what is deployed where

```mermaid
flowchart TB
    subgraph mac["one macOS host"]
        subgraph city["~/cities/ptl-city — the CITY"]
            sup["launchd: com.gascity.supervisor"]
            disp["core.control-dispatcher"]
            form["formulas/design-authoring.toml"]
            beads[("bead store<br/>Dolt")]
        end

        subgraph rig["~/cities/ptl-rig — the RIG, cwd for every check"]
            chk["checks/ · tooling/ · lib/ · catalog/ · tools/"]
            subgraph art["processes/&lt;name&gt; — artifact_root"]
                bound["checks/ — wrappers bound at cook time"]
                arts["QUESTIONS.md · design · verdict<br/>FINDINGS.md · BRIEF.md · diagrams/"]
                bundle["bundle/ — THE L2 ARTIFACT"]
            end
        end

        subgraph agents["tmux — agent sessions"]
            op["gc.run-operator<br/>provider: claude"]
            aud["audit lane<br/>provider: gemini"]
        end

        repo["~/software/process-to-loop<br/>the source of truth"]
    end

    subgraph ext["outside the host"]
        anth["Anthropic API"]
        goog["Google API"]
    end

    sup --> disp
    disp --> op
    form -.->|cooked into| beads
    beads --> op
    op -->|runs| bound
    bound -->|execs| chk
    op --> arts
    op -->|compile| bundle
    aud --> goog
    op --> anth
    repo -.->|make install-rig| chk
    repo -.->|make install-city| form
    bundle -.->|launchd job, once deployed| mac

    classDef regulated fill:#fee2e2,stroke:#b91c1c
    class bundle regulated
```

**Two facts this view exists to record**, both of which cost hours to learn:

- a check's **cwd is the rig**, not the city. Checks installed only in the city are never found.
- inside an agent, **`$HOME` is the city directory**. A keychain lookup resolving `~` finds
  `cities/ptl-city/Library/Keychains`, which does not exist.

---

## 5. +1 Scenarios — the tooling scripts in sequence

The scenario that ties the other four together: **one described process becomes a running
bundle.** Every lifeline is a real script.

```mermaid
sequenceDiagram
    autonumber
    actor P as Process owner
    participant OP as gc.run-operator
    participant BC as bind-checks.sh
    participant AR as archive-run.sh
    participant QS as questions.sh
    participant QA as questions-asked.sh
    participant QN as questions-answered.sh
    participant VA as validate.sh
    participant AU as audit-design.sh
    participant DR as design-reviewed.sh
    participant BR as brief.sh
    participant FI as findings.sh
    participant AC as accept.sh
    participant CO as compile.sh
    participant EB as emit-bundle.sh
    participant BRC as bundle-records.sh

    Note over OP,BC: bind-checks — every value known at cook time
    OP->>BC: artifact_root, checks_root, DESIGN_PATH, QUESTIONS_PATH, — CATALOG, METHOD_PATH, BUNDLE_PATH
    BC-->>OP: one wrapper per check, values bound literally

    Note over OP,AR: archive-prior — the last run beyond reach
    OP->>AR: artifact_root
    AR-->>OP: prior/TIMESTAMP/ copied — verdict and findings REMOVED, — QUESTIONS.md kept

    Note over OP,QA: intake, then the interview
    OP->>OP: read use-case.txt, screen for text addressing the system
    OP->>QS: write QUESTIONS.md.new, then merge
    QS-->>OP: answers survive, ids stable, refuses losing one
    OP->>QA: questions-asked.sh
    QA->>QS: validate (I1..I8)
    QA-->>OP: 0 askable · 1 malformed · 75 absent

    P->>QS: answer Qn stated|unanswered|delegated --by --synthetic
    OP->>QN: questions-answered.sh
    QN->>QS: answered (A1..A7) + status
    QN-->>OP: 0 every block answered, with the ratio

    rect rgb(245,245,245)
    Note over OP,DR: THE LOOP — up to 5 attempts
    OP->>OP: author the design (author provider)
    OP->>DR: design-reviewed.sh
    DR->>VA: validate.sh (QUESTIONS, CATALOG, METHOD)
    VA-->>DR: 45 rules
    DR->>AU: audit-design.sh, only if the design is stale
    AU->>AU: credential.sh, then the AUDIT provider
    AU-->>DR: verdict stamped subject_sha256
    DR-->>OP: 1 = a revision can fix it · 0 = only a person can
    end

    OP->>VA: design-validate.sh (the durable record)
    OP->>OP: design-audited.sh — real, different model, THIS design
    OP->>BR: brief.sh --questions
    BR-->>OP: BRIEF.md with the interview table, both diagrams
    OP->>OP: diagrams-complete.sh — every control is drawn
    OP->>FI: findings.sh --questions
    FI-->>OP: FINDINGS.md: audit + delegated structural + — unanswered + synthetic + rehearsal

    Note over P,AC: ACCEPTANCE — a person, over content
    P->>AC: accept.sh DESIGN --by "Name, Role"
    AC->>AC: signer == meta.approver? rules pass? rehearsal?
    AC-->>P: chained register row, with any REHEARSAL note

    Note over OP,BRC: compile — only after the signature
    OP->>CO: compile.sh
    CO->>CO: refuse if REHEARSAL and ALLOW_REHEARSAL unnamed
    CO-->>OP: formula + one check per gate + decision tables
    OP->>EB: emit-bundle.sh
    EB->>EB: resolve tools and skills through the catalog, once
    EB-->>OP: run.sh, steps/, lib/dt-cell.awk, launchd job
    OP->>BRC: bundle-records.sh
    BRC->>BRC: RUN ONE TICK, then read the ledger
    BRC-->>OP: provenance, permissions, skills in force
```

### The same scenario at L2 — one tick

```mermaid
sequenceDiagram
    autonumber
    participant LD as launchd
    participant RUN as run.sh
    participant ST as steps/N-*.sh
    participant TL as a catalogued tool
    participant CK as checks/NAME-gNN.sh
    participant DEC as lib/decide.awk
    participant LG as memory/ledger.tsv

    LD->>RUN: tick
    RUN->>ST: batch steps, in order
    ST->>TL: fetch
    alt the tool is not installed
        TL-->>ST: exit 75
        ST->>LG: deferred
        ST-->>RUN: 75 — infrastructure, never a business failure
    else it answers
        TL-->>ST: rows
        ST->>LG: read "SOURCE via TOOL (CLASS — may not CONSTRAINT): N row(s)"
    end
    ST->>CK: gate condition
    alt the check is not installed
        CK-->>ST: absent
        ST->>LG: refused "check script missing"
        ST-->>RUN: stop — a control that does not exist does not permit
    else a decision table backs it
        CK->>DEC: inputs
        alt no rule matches
            DEC-->>CK: exit 1
            CK-->>ST: REFUSE — a fall-through is a refusal, never a default
        else a rule matches
            DEC-->>CK: outputs
            CK-->>ST: permit or refuse on the gated value
        end
    end
    RUN->>ST: unit steps, per unit
    ST->>LG: skill "ID (OWNER) catalog SHA: in force, not verified as applied"
    ST->>LG: unit row — references and outcomes only, never PHI in clear
```

---

## What the views disagree about, and why that is deliberate

The **logical** view shows a clean chain of digests. The **process** view shows a loop that can
fail at seven places. The **development** view shows one shared definition (`dt-cell.awk`) that
deliberately crosses the L1/L2 boundary. The **physical** view shows that a check's cwd and an
agent's `$HOME` are not what anybody assumes.

Those tensions are the architecture. The chain is clean *because* the loop refuses; the shared
definition crosses the boundary *so that* the rules and the emitted check cannot diverge; and the
cwd facts are recorded *because* every expensive defect in this project lived exactly there.
