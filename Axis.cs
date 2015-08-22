using UnityEngine;

public class Axis {
	public enum Dir
	{
		Right,
		Left,
		Up,
		Down,
		Forward,
		Back
	}

	public Dir dir;

	public Vector3 Vector
	{ get {
			switch(dir)
			{
			case Axis.Dir.Forward:
				return Vector3.forward;
			case Axis.Dir.Back:
				return Vector3.back;
			case Axis.Dir.Up:
				return Vector3.up;
			case Axis.Dir.Down:
				return Vector3.down;
			case Axis.Dir.Left:
				return Vector3.left;
			default:
				return Vector3.right;
			} 
		}
	}

	public Axis(Dir assignDir)
	{
		dir = assignDir;
	}
}
