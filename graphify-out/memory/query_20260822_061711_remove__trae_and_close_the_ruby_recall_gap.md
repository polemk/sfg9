---
type: "query"
date: "2026-08-22T06:17:11.851960+00:00"
question: "Remove .trae and close the Ruby recall gap"
contributor: "graphify"
outcome: "useful"
source_nodes: ["Credential", "Integration", "TokenService"]
---

# Q: Remove .trae and close the Ruby recall gap

## Answer

BOTH DONE. (1) .trae removed as obsolete: 1340 nodes (1308 under .trae/, 32 under backend/.trae/), 1250 links and 1 hyperedge (comment_to_dm_private_reply_flow, which was entirely roadmap-029 content recovered earlier from cache). manifest.json also filtered. 0 .trae nodes remain. (2) Ruby recall closed to 100%. Two findings on the way: (a) The instance-variable worry was misdiagnosed by me. Measured it: 247 @ivar.method call sites exist, but almost none are assigned from Const.new - they come from constructor parameters (@session = session, @lead = lead, @text = text). The receiver type is whatever the caller passed, which is duck-typed constructor injection, not statically resolvable without whole-program inference. The two exceptions (@user = User.find_by, @current_client = ClientApplication.active.find_by) are class-method calls ALREADY captured as constant-receiver edges, so the file pair is already linked. There is no real recall gap here; guessing @session's type would reintroduce fabrication. (b) The 110 genuinely missing file pairs had a concrete cause: in Rails models the class node and the file node BOTH sit on line 1, and the by-line lookup used setdefault so the FILE node won. Target resolution then produced 'credential.rb' instead of 'Credential', and the call-site check could not confirm it. Fixed by preferring the class-labelled node; second additive pass added 162 edges, all 162 call-site confirmed, 0 rejected. FINAL: directed=true, 5703 nodes, 10344 edges, 12 hyperedges, 651 communities. Ruby cross-file call recall 816/816 = 100%. TypeScript 543/543 = 100%. Precision 0 false out of 2234 checked. Integrity all zero. Connectivity improved sharply: largest component 35.7% -> 44.7%, isolated nodes 204 -> 179, components 533 -> 418. LABELLING LESSON: community labels must be keyed by CONTENT SIGNATURE, not community id - ids are reassigned on every re-cluster, so id-keyed names silently drift onto the wrong groups. Fallback labels now use the dominant directory at a useful depth plus the highest-degree member, never a bare 'backend' or 'Misc N'.

## Outcome

- Signal: useful

## Source Nodes

- Credential
- Integration
- TokenService