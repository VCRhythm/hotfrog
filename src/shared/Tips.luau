--!strict
-- ReplicatedStorage/Shared/Tips (ModuleScript)
-- Short gameplay tips for the end-of-run panel (MenuClient). A port addition --
-- Unity has no tips (b-20261010-192336-pgwh, doc 17). Every line states
-- something the port's code really does; if a rule it cites changes (a Config
-- number, a step behaviour, a level threshold), update the tip too. Keep each
-- under ~90 characters so it fits the panel's Tips area on two or three lines.

local Tips = {}

Tips.list = {
	-- Config.GRAB_PERFECT_SQR / GRAB_GREAT_SQR, PullMath.gradeGrab: tap-to-grip distance.
	"Tap right on a step's grip point for a Perfect grab. The farther off, the lower the grade.",
	-- GameServer frog sim: death needs the lava line reached with nothing held.
	"The frog only dies when it sinks into the lava with nothing held. Keep a hand on a step.",
	-- Config.EXPLODE_FUSE = 1 (StepBehaviors.ExplodeAfterGrab, params.burst "Pebble"):
	-- StepKinds.CrumbleRock and CrumblyRock, the pebble-cluster art, in Kitchen and Country.
	"Pebbly rock clusters in the Kitchen and Country shake, then burst 1 second after you grab them.",
	-- Config.EXPLODE_FUSE = 1 (StepBehaviors.ExplodeAfterGrab): StepKinds.Potato, Pot only.
	"Potatoes in the Pot shake when you grab them and explode 1 second later.",
	-- StepBehaviors.Vanish (StepKinds.BlinkRock, violet tint, Country and Space;
	-- StepKinds.IceCube in the Kitchen): shakes after 3 s in view, drops 1.5 s later.
	"Ice cubes and violet rocks start shaking after a few seconds on screen, then drop away.",
	-- StepBehaviors.Beetle (StepKinds.Beetle, Country from its second stage): the
	-- first grab is a forced release, later grabs hold.
	"Ladybugs in the Country shrug off your first grab. Grab again and they hold.",
	-- StepBehaviors.ChangeDirection*: grabbing sets the lane's scroll direction.
	"Grabbing an arrow step changes the direction the world scrolls. Plan your next grab.",
	-- Config.BUG_FLYS = 5.
	"Tap a passing bug to catch it. Most are worth 5 Flys.",
	-- Config.GOLDEN_BUG_FLYS = 25, shorter lifespan, faster Dart pattern.
	"Golden bugs are rare and quick to leave, but they pay 25 Flys.",
	-- BugService "Skittish" pattern, Config.BUG_SKITTISH_RADIUS.
	"Skittish bugs drift away from your frog's hands. Tap them from a distance.",
	-- SkinCatalog flyCost.
	"Spend your Flys on new frog skins in the Shop.",
	-- Config.LEVEL_THRESHOLDS = { Kitchen = 50, Country = 100, Space = 250 }; Pot -> Kitchen fires on the pot-rim grab.
	"After 50 steps the pot rim appears: grab it to reach the Kitchen. Country starts at 100, Space at 250.",
	-- StepBehaviors.Drive + Config.CAR_KNOCK_TIME (Country cars).
	"Cars in the Country keep driving. Hop off before they shake you loose.",
	-- Chef.luau: the tell, then a blow that lands on the target even if it is held.
	"In the Kitchen, the Chef shows his move first. Stay off the step he targets.",
	-- Chef.luau actions: Knife / Food / Shove.
	"The Chef can chop a step, throw a potato at it, or shove it sideways. Watch his wind-up.",
}

-- A random tip, never the one at `previous` (when there is more than one).
-- Returns the text and its index so the caller can pass it back next time.
function Tips.pick(previous: number?): (string, number)
	local count = #Tips.list
	local index = math.random(1, count)
	if count > 1 and index == previous then
		index = index % count + 1
	end
	return Tips.list[index], index
end

return Tips
