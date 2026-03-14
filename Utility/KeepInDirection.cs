using UnityEngine;

namespace HotFrog.Utility
{
	public class KeepInDirection : MonoBehaviour
	{
		private Transform _transform;

		[SerializeField] private Vector2 direction = Vector2.up;

		private void Awake() => _transform = transform;

		private void Update() => _transform.up = direction;
	}
}
