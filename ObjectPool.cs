using UnityEngine;
using System.Collections.Generic;

public class ObjectPool : MonoBehaviour
{
    public string poolName; // For reference only
    public int initialPoolSize = 10;
    public PooledObject[] pooledObjectPrefabs;
    public Transform parent = null;

    public Stack<PooledObject>[] PooledObjects { get; private set; }
    public List<PooledObject> ActiveObjects { get; private set; }

    [ReadOnly] public int poolSize = 0;

    public bool canGrow = false;

    Dictionary<GameObject, PooledObject> poolObjectLookup = new Dictionary<GameObject, PooledObject>();
    int TotalObjects
    {
        get
        {
            int sum = 0;
            for (int i = 0; i < PooledObjects.Length; i++)
                sum += PooledObjects[i].Count;
            return sum;
        }
    }

    void Awake()
    {
        if (initialPoolSize < pooledObjectPrefabs.Length)
        {
            initialPoolSize = pooledObjectPrefabs.Length;
        }

        ActiveObjects = new List<PooledObject>();
        PooledObjects = new Stack<PooledObject>[pooledObjectPrefabs.Length];
        for (int i = 0; i < pooledObjectPrefabs.Length; i++)
        {
            PooledObjects[i] = new Stack<PooledObject>();
        }

        for (int i = 0; i < initialPoolSize; i++)
        {
            Grow(false);
        }
    }

    public Transform GetTransformAndSetPosition(Vector3 position, int index = -1)
    {
        PooledObject obj = Pop(index);
        if (obj != null)
        {
            obj.SetPositionAndActivate(position);
            return obj.transform;
        }
        return null;
    }

    public void Insert(GameObject gameObject)
    {
        if (gameObject.activeInHierarchy)
        {
            gameObject.SetActive(false);
        }

        PooledObject obj = poolObjectLookup[gameObject];
        ActiveObjects.Remove(obj);
        Push(obj);
    }

    private PooledObject Pop(int requestedIndex = -1)
    {
        int index = requestedIndex >= 0 && requestedIndex < PooledObjects.Length ? requestedIndex : Random.Range(0, PooledObjects.Length);

        if (PooledObjects[index].Count > 0)
        {
            PooledObject obj = PooledObjects[index].Pop();
            ActiveObjects.Add(obj);
            return obj;
        }

        if (canGrow)
        {
            PooledObject obj = Grow(true, requestedIndex);
            ActiveObjects.Add(obj);
            return obj;
        }

        return null;
    }

    private void Push(PooledObject obj)
    {
        obj.gameObject.SetActive(false);
        PooledObjects[obj.index].Push(obj);
    }

    private PooledObject Grow(bool isPopped, int index = -1)
    {
        if (index < 0)
            index = TotalObjects % pooledObjectPrefabs.Length;

        PooledObject obj = Instantiate(pooledObjectPrefabs[index]) as PooledObject;
        obj.index = index;

        if (parent != null) obj.transform.SetParent(parent);
        obj.Pool = this;

        poolObjectLookup.Add(obj.gameObject, obj);

        poolSize++;

        if (!isPopped)
        {
            Push(obj);
            return null;
        }

        return obj;
    }
}