using UnityEngine;

public class TouchInput : MonoBehaviour, IUserInput {
	public int InputCount { get { return Input.touchCount; } }
	public bool IsTouchInput { get { return true; } }

	public Vector2 GetPosition(int touchIndex)
	{
		return Input.GetTouch(touchIndex).position;
	}

	public bool HasInputStarted(int touchIndex)
	{
		return Input.GetTouch(touchIndex).phase == TouchPhase.Began;
	}

	public bool IsInputOn(int touchIndex)
	{
		TouchPhase phase = Input.GetTouch (touchIndex).phase;
		return phase == TouchPhase.Began || phase == TouchPhase.Moved || phase == TouchPhase.Stationary;
	}
}
