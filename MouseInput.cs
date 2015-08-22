using UnityEngine;

public class MouseInput : MonoBehaviour, IUserInput {
	public int InputCount { get { return 2; } }
	public bool IsTouchInput { get { return false; } }

	public Vector2 GetPosition(int touchIndex)
	{
		return Input.mousePosition;
	}

	public bool HasInputStarted(int touchIndex)
	{
		return Input.GetMouseButtonDown(touchIndex);
	}

	public bool IsInputOn(int touchIndex)
	{
		return Input.GetMouseButton(touchIndex);
	}
}
