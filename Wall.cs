using UnityEngine;

public class Wall : MonoBehaviour {

	public Transform wallToTop;
	public Transform wallToLeft;
	public Transform wallToRight;

	MeshRenderer meshRenderer;
	Transform _transform;

	void Awake()
	{
		meshRenderer = GetComponent<MeshRenderer>();
		_transform = transform;
	}

	void Update()
	{
		Vector3 vector = -SpawnManager.Instance.pullVector * Time.deltaTime * .1f;
		_transform.Translate(vector.x, 0, vector.y);

		if(_transform.localPosition.z > 9.9f)
		{
			_transform.localPosition = new Vector3(_transform.localPosition.x, -1f, wallToTop.localPosition.z - 9.9f);
		}

		if(_transform.localPosition.x > 15f)
		{
			_transform.localPosition = new Vector3(wallToRight.localPosition.x - 9.9f, -1f, _transform.localPosition.z);
		}
		else if(_transform.localPosition.x < -15f)
		{
			_transform.localPosition = new Vector3(wallToLeft.localPosition.x + 9.9f, -1f, _transform.localPosition.z);
		}
	}
	
	public void SetMaterial(Material material)
	{
		if(material == null)
			meshRenderer.enabled = false;
		else
		{
			meshRenderer.material = material;
			meshRenderer.enabled = true;
		}
	}
}
