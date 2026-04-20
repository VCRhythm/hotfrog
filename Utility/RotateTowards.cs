using UnityEngine;

namespace HotFrog.Utility
{
	public class RotateTowards : MonoBehaviour
	{
		private Transform _transform;
		private Rigidbody2D parentRB;

		[SerializeField] private float rotateSpeed = 100f;
		private float velocity;

		[SerializeField] private Vector3 direction;
		[SerializeField] private bool checkParent = false;

		private void Awake() => _transform = transform;

		private void Update()
		{
			_transform.rotation = Quaternion.Lerp(_transform.rotation, Quaternion.Euler(direction), Time.time * rotateSpeed);
		}
	}
}
