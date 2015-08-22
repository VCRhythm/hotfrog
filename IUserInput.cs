using UnityEngine;

public interface IUserInput {
	int InputCount { get; }
	bool IsTouchInput { get; }
	bool HasInputStarted(int touchIndex);
	bool IsInputOn(int touchIndex);
	Vector2 GetPosition(int touchIndex);
}