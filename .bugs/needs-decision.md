# hotfrog — questions the bug loop needs answered


## b-20261012-162429-k6wc  2026-10-12 16:26
note: Client-reported tapPos lets a modified client always grade Perfect, which now also maxes the Normal combo streak (+3) and its score bonus (up to +5/grab) that feeds the leaderboards
question: The grab grade comes from where the client says it tapped, which the server cannot check, so a hacked client can claim Perfect on every grab. Since the combo (b99c6e5) that is worth up to ~6 score per grab instead of 1 on the shared best-score boards. Pick one: a) accept it (it was already spoofable; boards are casual); b) leaderboards and best score count steps only, and the combo bonus shows on the HUD and run summary but is not saved; c) a cheap server heuristic: a player whose Perfect rate over the last 20 grabs is implausibly high (e.g. >90%), or whose tap lands within 0.01 studs of the grip, gets those grabs credited as Great for streak and bonus. It stops naive cheats, but a careful cheater can add jitter.
context: GameServer.server.luau ~1830 grades with PullMath.gradeGrab(tapPos, gripNow). Steps themselves are server-checked (reach, rate limit 10/s), so a step-only board (b) cannot be inflated by grading. Normal and Classic share one highScore and one set of boards.
recommendation: c: it keeps your combo bonus on the boards as asked, costs a few lines and blocks the obvious exploit; choose b if fair boards matter more than showing the bonus there.
