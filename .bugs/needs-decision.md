# hotfrog — questions the bug loop needs answered

## b-20260921-111337-hqcb  2026-09-21 11:55
note: the unity game gives the frog a sway and bob with each grab
question: Unity's Frog.Bob (Frog.cs:254-279) sways the head+body to the grabbed step's X, gives it a Z-rotation "rock" punch, and bobs it up only when the head has sunk below −5u. Unity's frog keeps sinking while it holds a step; the port stops gravity while holding (doc 17 Pause / Death-condition rows), so the bob would almost never trigger. Choose: (A) full port in GameServer, including gravity continuing while holding (reverses those doc 17 rows; fall speed needs retuning); (B) sway + rock only, server render loop, with a new unswayed anchor for the client readers; (C) omit, record as a deviation in doc 17.
context: GameServer GrabStep/ReleaseStep plus the render Heartbeat that pins Head/Body to f.pos; Body is the PrimaryPart that GrabTarget/WorldTouchIndicator/WorldQualityPopup/WorldLava read as the frog's position.
