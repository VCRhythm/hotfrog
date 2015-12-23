using UnityEngine;

public abstract class PooledObject : MonoBehaviour
{
    [ReadOnly] public int index;
    public System.Action deregisterAction = () => { };
    [ReadOnly] public ObjectPool Pool;

	public bool IsActive { get { return gameObject.activeInHierarchy; } set { gameObject.SetActive(value); } }
	
	public void SetPositionAndActivate(Vector3 position)
	{
		transform.position = position;
		gameObject.SetActive(true);
	}

    public virtual void Destroy()
    {
        if (Pool != null) Pool.Insert(gameObject);
    }
}