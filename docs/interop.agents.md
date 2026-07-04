# Interop research — plugging sysml-lean into the off-the-shelf MBSE/STPA ecosystem

Working notes, July 2026. Claims verified via web search where possible; unverified items flagged. Context: the project (Lean 4, custom SysML v2-flavored DSL, STPA type-checker, emits `.sysml`/DOT/Mermaid/SVG/markdown/GSN, JSON verdicts, MontiCore second-source parser validation) currently has no import path from external tools and no export beyond SysML v2 text + diagrams.

## 1. Astah System Safety — the tool the market-research pass missed

Change Vision (Japan) ships **Astah System Safety**, bundling GSN, STAMP/STPA, ASAM SCDL, and SysML diagrams in one tool [Astah products](https://astah.net/products/astah-system-safety/). It is not a diagramming-only tool — it has real interchange surface:

- **XMI 2.5 export/import**, explicitly compatible with Cameo Systems Modeler, covering six SysML diagram kinds (BDD, IBD, Activity, Parametric, Requirement, Sequence) [Astah reference manual](https://astah.net/manual/sysml-and-system-safety/reference.html).
- **Import/export to OMG SACM 1.0** and **import from Astah GSN**, plus **SCDL import from Safilia** [Astah reference manual](https://astah.net/manual/sysml-and-system-safety/reference.html).
- Bidirectional conversion between SysML models and STAMP/STPA or SCDL models within the tool.

Market position: Astah is the *de facto platform* IPA (Japan's Information-technology Promotion Agency) built on. IPA's own STAMP Workbench — released 2018, still the reference free STPA tool in Japan — "uses Astah as its platform" [Astah blog on STAMP Workbench](https://astahblog.com/2018/04/09/stamp-workbench-by-ipa/). IPA has run at least three STAMP Workshops with major Japanese industrial participants (JR East, NTT Data) [IPA STAMP workshops](https://www.ipa.go.jp/en/digital/complex_systems/stamp_workshop-3.html). This makes Astah the single highest-leverage STPA-native interop target: it already speaks SACM XML and XMI 2.5, both of which are things we could plausibly emit.

## 2. SysML v2 native interchange

OMG formally adopted **KerML v1.0**, **SysML v2.0**, and the **Systems Modeling API and Services v1.0** by July 2025, with editorial ISO-submission updates in March 2026 [OMG adoption announcement](https://www.omg.org/news/releases/pr2025/07-21-25.htm), [SysML v2 specs page](https://sysml.org/sysml-specs/). Reference/pilot repos:

- [`Systems-Modeling/SysML-v2-Pilot-Implementation`](https://github.com/Systems-Modeling/SysML-v2-Pilot-Implementation) — textual notation + visualization, Maven-built. This is the closest thing to a canonical grammar oracle, playing the same role for the OMG spec that our MontiCore second-source parser plays for us.
- [`Systems-Modeling/SysML-v2-API-Services`](https://github.com/Systems-Modeling/SysML-v2-API-Services) — proof-of-concept REST/HTTP PSM of the API (Play framework, PostgreSQL backend). It is the pilot *reference server*, not a production one.
- [`Systems-Modeling/SysML-v2-API-Cookbook`](https://github.com/Systems-Modeling/SysML-v2-API-Cookbook) — worked API-call recipes.
- Complementary: OASIS's **OSLC SysML v2.0** spec defines lightweight RDF/Turtle resource shapes and REST bindings, distinct from and lighter-weight than the OMG API; status is PSD01 draft, early-stage adoption [OSLC SysML v2.0 spec](https://docs.oasis-open-projects.org/oslc-op/sysml/v2.0/sysml-spec.pdf).

Who implements the API today, verified:
- **Dassault CATIA Magic/Cameo 2026** — claims "100% of the SysML v2 standard" with two-way textual/graphical sync, but *only* on specific license bundles (M2E-N/C, M3E-N/C); base Cameo Architect and MagicDraw+SysML-plugin do **not** get v2 [GoEngineer](https://www.goengineer.com/blog/advantages-of-sysml-v2-now-available-in-no-magic-cameo-and-catia-magic-2026), [NoMagic docs](https://docs.nomagic.com/SYSML2P/2026x/catia-magic-cameo-sysml-v2-solution-272740940.html). Pricing on SysML v2-capable bundles rose ~20% Jan 2026.
- **Intercax Syndeia** — first commercial tool to integrate the SysML v2 API (2021, Syndeia 3.4), API-first, REST-driven digital-thread platform, at release 3.7.1 as of June 2026 [Intercax blog](https://intercax.com/blog/sysml-v2-and-digital-threads-with-syndeia).
- **Sensmetry Syside** — Python API for programmatic model access/validation/CI, targeting a stable v1 in 2026; ReqIF import/export to Codebeamer/DOORS/Polarion/Cameo is an explicit Q2 2026 roadmap item; MCP servers for AI-assistant access are planned [Sensmetry roadmap](https://sensmetry.com/product-roadmap-2026-q2-update/).
- **SysON (Obeo/Eclipse)** — open source, built on Sirius Web, which exposes "a subset of the SysML v2 REST API" with auto-generated OpenAPI/Swagger docs; the team states the full API "is not fully available yet" [SysON API docs](https://doc.mbse-syson.org/syson/v2026.1.0/developer-guide/api/api-details.html). 8-week release cadence, industrial Early Adopter Program running through 2026.

Net: the *API* ecosystem is real but immature — one full commercial implementation (Syndeia, closed/paid), one partial open-source implementation (SysON), one API-in-progress (Syside). The *textual notation* (`.sysml` files) is comparatively mature and is what our project already emits.

## 3. SysML v1/UML legacy bridge

OMG published a formal **SysML v1-to-v2 Transformation** spec (Sept 2025, editorially updated as formal/2026-03-03), defining a four-stage pipeline: pre-process v1 model → transform → post-process to leverage v2 idioms → validate semantic fidelity [OMG transformation spec](https://www.omg.org/spec/SysML/2.0/Transformation/PDF), [OMG wiki conversion process](https://www.omgwiki.org/MBSE/doku.php?id=mbse%3Asysml_v2_transition%3Amodel_conversion_approach). CATIA Magic/Cameo 2026 supports v1/v2 *coexistence* in one environment, but that is authoring-time coexistence, not confirmed conformance to the OMG transformation spec end-to-end — flag as **unverified** whether any vendor tool implements the formal transformation spec directly rather than just parallel v1/v2 authoring. Given most installed base is still v1/Cameo/Rhapsody/Enterprise Architect, this remains the long pole for reaching legacy shops; XMI 2.5 (which Astah already round-trips) is the practical bridge available today.

## 4. Requirements-tool interchange

ReqIF is a live, well-supported interchange point: **Jama Connect Interchange for ReqIF** is a dedicated product for customer/supplier requirements exchange [Jama ReqIF datasheet](https://www.jamasoftware.com/datasheet/jama-connect-interchange-for-reqif/); **Codebeamer** supports ReqIF natively for cross-tool requirements/test-case migration [PTC Codebeamer integrations](https://www.ptc.com/en/products/codebeamer/integrations); Polarion is one of the "big four" web RM tools alongside DOORS Next, Jama, and Codebeamer, with comparable interchange expectations [reqSuite 2026 RM comparison](https://www.reqsuite.io/en/blog/requirements-management-tools-2026-a-comparison-for-medium-sized-product-developers). OSLC linking is alive but narrower — Codebeamer-Windchill OSLC integration exists, and IBM continues OSLC investment [PTC Codebeamer integrations](https://www.ptc.com/en/products/codebeamer/integrations). Notably, **Sensmetry's own 2026 roadmap targets ReqIF import/export to exactly this same set of tools** — meaning we could piggyback on Syside as a ReqIF hub rather than building bespoke exporters per target. Exporting our UCAs/constraints as ReqIF should land usably in Jama/Codebeamer/Polarion since ReqIF's "requirement + attributes + relations" shape maps cleanly onto UCA-type/context/hazard-link data we already compute.

## 5. Assurance-case interchange

**OMG SACM** (current: 2.1/2.2) is the standard behind both GSN and CAE; its Artifact Model compliance point defines import/export of XMI conforming to a SACM XML Schema [OMG SACM 2.2 spec](https://www.omg.org/spec/SACM/2.2/PDF). Two commercial tools confirmed to speak it:
- **Adelard ASCE** — dominant commercial GSN tool, has a dedicated "SACM Export plugin" mapping CAE elements to SACM [Argevide on GSN/SACM modular cases](https://www.argevide.com/2025-06-modular-assurance-cases/), and ASCE 5.1 adds GSN v3 support [Adelard ASCE 5.1 announcement](https://www.adelard.com/news/asce-51-delivers-enhanced-functionality-support-for-gsn-v3-and-next-generation-assurance-case-design/).
- **Astah System Safety** — imports/exports "OMG SACM 1.0" per its own docs [Astah reference manual](https://astah.net/manual/sysml-and-system-safety/reference.html) (note: Astah's docs cite "SACM 1.0" while OMG's current line is 2.x — version-naming mismatch, unverified whether this is a documentation lag or a genuinely older-schema export).

Given two independent commercial tools both accept SACM XML, this is the highest-confidence assurance-case interop target — better than targeting GSN's own (YAML/XML-ish, tool-specific) formats directly, since e.g. `gsn2x` uses plain YAML with no standard schema behind it [gsn2x GitHub](https://github.com/jonasthewolf/gsn2x).

## 6. Safety-analysis data interchange

No broadly-adopted standard exists for hazard logs/STPA artifacts specifically. The closest attempt, **Digital Dependability Identities (DDI)** and the **Open Dependability Exchange (ODE)** metamodel from the EU H2020 DEIS project (2016–2019, EMF/Ecore-based) [DEIS project results](https://cordis.europa.eu/project/id/732242/results), [WAP: Digital Dependability Identities](https://arxiv.org/pdf/2105.14984), appears dormant post-project — its GitHub tooling repo exists [DEIS-Project-EU/DDI-Scripting-Tools](https://github.com/DEIS-Project-EU/DDI-Scripting-Tools) but shows no visible 2024-2026 activity (unverified — not independently confirmed inactive, just no recent evidence surfaced). Treat DDI/ODE as academic-legacy, low priority. XSTAMPP (open-source Eclipse RCP, STPA+CAST plugins) stores an internal XML representation per STPA component, but no public schema documentation surfaced beyond "XML" [XSTAMPP GitHub](https://github.com/asimabdulkhaleq/XSTAMPP) — reading it would require reverse-engineering from source, which is feasible since it's open source. STAMP Workbench, being Astah-based, likely round-trips through Astah's own `.asta`/XMI/SACM paths rather than a separate schema [Astah blog on STAMP Workbench](https://astahblog.com/2018/04/09/stamp-workbench-by-ipa/) — unverified in detail, but structurally plausible given the platform relationship.

## 7. The unglamorous status quo

Excel/CSV remains the dominant real-world hazard-log and FMEA format: FAA publishes an Excel hazard-analysis template [FAA hazard analysis template](https://www.faa.gov/about/office_org/headquarters_offices/ast/media/Hazard%20Analysis%20Template.xls), ASQ and QI Macros ship FMEA Excel templates [ASQ FMEA template](https://asq.org/-/media/public/learn-about-quality/data-collection-analysis-tools/asq-fmea-template.xls), and commercial STPA tools like RM Studio auto-populate UCA tables from control-structure diagrams inside a spreadsheet-adjacent UI [RM Studio STPA](https://www.riskmanagementstudio.com/stpa-software-solution/). No cross-vendor CSV schema exists, but that's the point: a pragmatic, loosely-typed CSV importer (columns: control action, context, UCA type, hazard link, rationale) meets working safety engineers exactly where they already are — in spreadsheets, not in any standard.

## 8. Recommendation — ranked interop surfaces to build

1. **`.sysml` textual file import → extends the DSL parser.** Effort **M**. The textual notation is the most mature part of the OMG stack (finalized July 2025, exercised by our own MontiCore-validated emitter already) and is what CATIA Magic/Cameo 2026, Syside, and SysON all read/write today. Lets users hand us models authored in real tools instead of our DSL. Lowest-risk, highest-reach near-term bet.
2. **GSN → SACM XML export, extending `Sysml/Gsn.lean`.** Effort **S/M**. Two independent commercial tools (Astah, ASCE) already accept SACM XML — this is a transform of data we already compute, not new analysis, and lands directly in the two most-used assurance-case tools in the safety-critical space.
3. **ReqIF export of requirements/UCAs/constraints, extending the JSON-verdicts layer.** Effort **M**. Reaches Jama, Codebeamer, Polarion, DOORS — and Sensmetry's own 2026 roadmap targets the same set, so our exporter could double as a Syside-ecosystem input rather than needing per-vendor bespoke mappings.
4. **SysML v2 REST API as a client, from the Kernel model.** Effort **L**. Higher long-term leverage (live model-server sync beats static files) but the 2026 server landscape is thin: one paid production implementation (Syndeia), one partial open-source one (SysON, explicitly "not fully available yet"), one in-progress (Syside, targeting v1 later in 2026). Building a client now means integrating against unstable or closed targets. Revisit once SysON's subset stabilizes or Syside ships v1.
5. **CSV import of hazard/UCA tables.** Effort **S**. No standard to chase, but highest-reach onboarding wedge — meets engineers in the Excel/CSV they already use, per section 7.

**Is the SysML v2 REST API client higher-leverage than `.sysml` file import? No, not yet.** Three reasons: (a) engineering risk — `.sysml` text is a finalized, stable grammar we already emit and validate against MontiCore, while the API's production implementations are either closed/paid (Syndeia) or explicitly partial (SysON); (b) few live integration targets — building a client mainly gets us talking to Syndeia's paid cloud or a work-in-progress SysON deployment, not a broad install base; (c) workflow fit — file-based exchange (`.sysml`, XMI, ReqIF, SACM) matches the git/PR/CI-centric, offline-reviewable workflow this project's whole thesis depends on (per `docs/market-research.agents.md` §3's "Git/CI workflow presumption" point), whereas a REST API client presumes always-on connectivity and live accounts on commercial platforms — a heavier sales/access lift for less near-term reach. File import wins now; the API client becomes the better bet once SysON's API subset and Syside's v1 stabilize later in 2026.

## Sources

- [Astah System Safety product page](https://astah.net/products/astah-system-safety/)
- [Astah System Safety and Astah SysML 9.0.0 reference manual](https://astah.net/manual/sysml-and-system-safety/reference.html)
- [Astah blog: New STAMP/STPA modeling tool – STAMP Workbench – released! (IPA)](https://astahblog.com/2018/04/09/stamp-workbench-by-ipa/)
- [IPA: 3rd STAMP Workshop in Japan](https://www.ipa.go.jp/en/digital/complex_systems/stamp_workshop-3.html)
- [Object Management Group: Final Adoption of SysML v2 (press release, July 2025)](https://www.omg.org/news/releases/pr2025/07-21-25.htm)
- [SysML v1 & v2 Specs page](https://sysml.org/sysml-specs/)
- [GitHub: Systems-Modeling/SysML-v2-Pilot-Implementation](https://github.com/Systems-Modeling/SysML-v2-Pilot-Implementation)
- [GitHub: Systems-Modeling/SysML-v2-API-Services](https://github.com/Systems-Modeling/SysML-v2-API-Services)
- [GitHub: Systems-Modeling/SysML-v2-API-Cookbook](https://github.com/Systems-Modeling/SysML-v2-API-Cookbook)
- [OASIS OSLC SysML v2.0 specification (PDF)](https://docs.oasis-open-projects.org/oslc-op/sysml/v2.0/sysml-spec.pdf)
- [GoEngineer: Advantages of SysML v2 in No Magic Cameo & CATIA Magic 2026](https://www.goengineer.com/blog/advantages-of-sysml-v2-now-available-in-no-magic-cameo-and-catia-magic-2026)
- [No Magic docs: CATIA Magic/Cameo SysML v2 Solution (2026x)](https://docs.nomagic.com/SYSML2P/2026x/catia-magic-cameo-sysml-v2-solution-272740940.html)
- [Intercax blog: SysML v2 and Digital Threads with Syndeia](https://intercax.com/blog/sysml-v2-and-digital-threads-with-syndeia)
- [Sensmetry Product Roadmap Q2 2026](https://sensmetry.com/product-roadmap-2026-q2-update/)
- [SysON API details docs (v2026.1.0)](https://doc.mbse-syson.org/syson/v2026.1.0/developer-guide/api/api-details.html)
- [OMG: SysML v1 to SysML v2 Transformation spec (PDF)](https://www.omg.org/spec/SysML/2.0/Transformation/PDF)
- [OMG Wiki: SysML v1 to SysML v2 Model Conversion Process](https://www.omgwiki.org/MBSE/doku.php?id=mbse%3Asysml_v2_transition%3Amodel_conversion_approach)
- [Jama Connect Interchange for ReqIF datasheet](https://www.jamasoftware.com/datasheet/jama-connect-interchange-for-reqif/)
- [PTC Codebeamer ALM Integrations](https://www.ptc.com/en/products/codebeamer/integrations)
- [reqSuite: Requirements Management Tools 2026 comparison](https://www.reqsuite.io/en/blog/requirements-management-tools-2026-a-comparison-for-medium-sized-product-developers)
- [OMG SACM 2.2 specification (PDF)](https://www.omg.org/spec/SACM/2.2/PDF)
- [Argevide: GSN and SACM modular assurance cases (2025)](https://www.argevide.com/2025-06-modular-assurance-cases/)
- [Adelard: ASCE 5.1 delivers GSN v3 support](https://www.adelard.com/news/asce-51-delivers-enhanced-functionality-support-for-gsn-v3-and-next-generation-assurance-case-design/)
- [gsn2x GitHub repository](https://github.com/jonasthewolf/gsn2x)
- [CORDIS: DEIS project results](https://cordis.europa.eu/project/id/732242/results)
- [arXiv: WAP — Digital Dependability Identities](https://arxiv.org/pdf/2105.14984)
- [GitHub: DEIS-Project-EU/DDI-Scripting-Tools](https://github.com/DEIS-Project-EU/DDI-Scripting-Tools)
- [GitHub: asimabdulkhaleq/XSTAMPP](https://github.com/asimabdulkhaleq/XSTAMPP)
- [FAA Hazard Analysis Template (XLS)](https://www.faa.gov/about/office_org/headquarters_offices/ast/media/Hazard%20Analysis%20Template.xls)
- [ASQ FMEA Template (XLS)](https://asq.org/-/media/public/learn-about-quality/data-collection-analysis-tools/asq-fmea-template.xls)
- [Risk Management Studio: STPA Software Solution](https://www.riskmanagementstudio.com/stpa-software-solution/)
- [Project market-research working notes (this repo)](../docs/market-research.agents.md)
