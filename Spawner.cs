using UnityEngine;
using System.Collections;
using System.Collections.Generic;
using DG.Tweening;

[RequireComponent(typeof(ObjectPool))]
public class Spawner : MonoBehaviour
{

    #region Fields

    public enum Type
    {
        None,
        Bug,
        Step,
        Scenery
    }
    public Type spawnerType;
    public Vector2 spawnDirection = new Vector2(0, -1f);
    public bool hasDiscreteMovement = false;

    public List<Vector3> Movements = new List<Vector3>();
    [ReadOnly]
    public List<Vector3> adjustedMovements = new List<Vector3>();
    protected Dictionary<Vector2, List<Vector3>> movementsPerDirection = new Dictionary<Vector2, List<Vector3>>();

    public float moveTimeMin = 1f;
    public float moveTimeMax = 2f; 
    public float moveSpeedMin = 1f;
    public float moveSpeedMax = 2f;
    public float maxSpawn = -1;
    public float spawningSpeedMin = 2f;
    public float spawningSpeedMax = 2f;
    protected float savedSpawningSpeedMin;
    protected float savedSpawningSpeedMax;

    [ReadOnly]
    public bool canSpawn = false;
    protected bool spawnsCanMove = true;
    protected int spawnCount = 0;
    private float lastSpawnTime;

    protected ObjectPool objectPool;
    private List<float> spawnProbabilities = new List<float>();

    protected Transform _transform;
    protected float halfScreenWidth;
    protected float halfScreenHeight;

    #endregion Fields

    #region Component Segments

    void Awake()
    {
        _transform = transform;
        objectPool = GetComponent<ObjectPool>();

        savedSpawningSpeedMin = spawningSpeedMin;
        savedSpawningSpeedMax = spawningSpeedMax;

        SetMovementToScreenSize();
        SetUpSpawnProbabilities();
    }

    #endregion Component Segments

    #region Functions

    public virtual void Reset(bool delayFade)
    {
        Debug.Log("Destroying spawns from " + name);
        CancelInvoke();
        canSpawn = false;

        DestroySpawns(delayFade);

        spawningSpeedMin = savedSpawningSpeedMin;
        spawningSpeedMax = savedSpawningSpeedMax;

        spawnCount = 0;
    }

    public virtual void Activate(bool canMove) { }

    public virtual void StartClimb()
    {
        canSpawn = true;
        if (adjustedMovements.Count > 0)
            Invoke("Move", Random.Range(moveTimeMin, moveTimeMax));
        
        StartCoroutine(StartSpawning(false));
    }

    public void CycleThroughMovementsAndSpawn(int spawnIndex = -1)
    {
        for (int i = 0; i < adjustedMovements.Count; i++)
        {
            SetPosition(adjustedMovements[i]);
            CreateSpawn(spawnIndex >= 0 ? spawnIndex : i);
        }
    }

    #endregion Functions

    #region Private Functions

    protected void Move()
    {
        Vector3 destination;
        do
        {
            destination = adjustedMovements[Random.Range(0, adjustedMovements.Count)];
        } while (destination == _transform.position && adjustedMovements.Count > 1);
        float speed = Random.Range(moveSpeedMin, moveSpeedMax);
        float nextMoveTime = Random.Range(moveTimeMin, moveTimeMax);

        if (!hasDiscreteMovement)
            _transform.DOLocalMove(destination, speed).OnComplete(() => { Invoke("Move", nextMoveTime); });
        else
        {
            SetPosition(destination);
            Invoke("Move", nextMoveTime);
        }
    }

    private void ControlSpawns(System.Action<Spawn> action)
    {
        for (int i = objectPool.ActiveObjects.Count - 1; i >= 0; i--)
        {
            action(objectPool.ActiveObjects[i].gameObject.SpawnScript());
        }
    }

    private void DestroySpawns(bool delayFade)
    {
        if (delayFade)
            ControlSpawns((x) => x.FadeAndDestroy(1f, 1f, 1f));
        else
            ControlSpawns((x) => x.Destroy());
    }

    protected virtual void SetMovementToScreenSize()
    {
        halfScreenWidth = 50 * ((float)Screen.width / Screen.height);
        halfScreenHeight = 50;
    }

    protected void SetPosition(Vector3 destination)
    {
        _transform.position = destination;
    }

    protected virtual IEnumerator StartSpawning(bool isFresh)
    {
        if (spawnCount > 0 && isFresh)
        {
            DestroySpawns(false);
        }

        while (enabled && (spawnCount < maxSpawn || maxSpawn < 0))
        {
            if (Time.time - lastSpawnTime > spawningSpeedMin)
                CreateSpawn();
            yield return new WaitForSeconds(Random.Range(spawningSpeedMin, spawningSpeedMax));
        }
        CancelInvoke("Move");
    }

    protected virtual Transform CreateSpawn(int spawnIndex = -1)
    {
        if (!canSpawn) return null;

        if (spawnIndex == -1 && spawnProbabilities.Count > 1)
        {
            float spawnChoice = Random.value;
            do
            {
                spawnIndex++;
                spawnChoice -= spawnProbabilities[spawnIndex];
            } while (spawnProbabilities.Count > spawnIndex + 1 && spawnChoice > 0);
        }
        
        Transform spawn = objectPool.GetTransformAndSetPosition(_transform.position, spawnIndex);
        spawnCount++;

        if (!spawnsCanMove) spawn.SpawnScript().PauseMovement();

        lastSpawnTime = Time.time;

        return spawn;
    }

    private void SetUpSpawnProbabilities()
    {
        float totalProbabilities = 0;
        for (int i = 0; i < objectPool.PooledObjects.Length; i++)
        {
            float probability = objectPool.PooledObjects[i].Peek().transform.SpawnScript().spawnProbability;
            spawnProbabilities.Add(probability);
            totalProbabilities += probability;
        }
        float probabilityMod = 1 / totalProbabilities;
        for (int i = 0; i < spawnProbabilities.Count; i++)
        {
            spawnProbabilities[i] *= probabilityMod;
        }
    }

    #endregion Private Functions
}