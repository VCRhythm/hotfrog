[System.Serializable]
public class LevelEvent {
	public bool triggersOnTime = true;
	public float trigger = 0;
	public System.Action action;

	public LevelEvent(bool triggersOnTime, float trigger, System.Action action)
	{
		this.triggersOnTime = triggersOnTime;
		this.trigger = trigger;
		this.action = action;
	}
}