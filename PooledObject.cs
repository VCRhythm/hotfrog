using UnityEngine;

public abstract class PooledObject : MonoBehaviour
{
    [ReadOnly] public int index;
    public System.Action deregisterAction = () => { };
    [ReadOnly] public ObjectPool Pool;
    public GameObject _gameObject { get; private set; }
    public Transform _transform { get; private set; }
    
	public bool IsActive { get { return gameObject.activeInHierarchy; } set { gameObject.SetActive(value); } }
	
	public void SetPositionAndActivate(Vector3 position)
	{
		transform.position = position;
		gameObject.SetActive(true);
	}

    protected virtual void Awake()
    {
        _gameObject = gameObject;
        _transform = transform;
    }

    public virtual void Destroy()
    {
        if (Pool != null) Pool.Insert(_gameObject);
    }

}