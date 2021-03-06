﻿using UnityEngine;
using System.Collections;
using System.Collections.Generic;

[RequireComponent(typeof(ObjectPool))]
public class SpeckManager : LevelObject {
    public Color[] colorOptions;

    private ObjectPool speckPool;
    private List<Speck> specks = new List<Speck>();
    
    void Awake()
    {
        speckPool = GetComponent<ObjectPool>();
    }
	
    public void ActivateSpecks(Vector2 position)
    {
        for(int i = 0; i < speckPool.initialPoolSize; i++)
        {
            Transform speck = speckPool.GetTransformAndSetPosition(position) as Transform;
            speck.GetComponent<SpriteRenderer>().color = colorOptions[Random.Range(0, colorOptions.Length - 1)];
            specks.Add(speck.GetComponent<Speck>());
        }
    }

    public void ActivateSpecks(Transform target)
    {
        for (int i = 0; i < speckPool.initialPoolSize; i++)
        {
            Transform speck = speckPool.GetTransformAndSetPosition(Vector2.zero) as Transform;
            speck.GetComponent<SpriteRenderer>().color = colorOptions[Random.Range(0, colorOptions.Length - 1)];
            specks.Add(speck.GetComponent<Speck>());
        }
        MoveSpecks(target);
    }

    public void DeactivateSpecks()
    {
        speckPool.InsertAllActiveObjects();
    }

    public override void Destroy()
    {
        DeactivateSpecks();
        Destroy(gameObject, 1f);
    }

    public void MoveSpecks(Vector2 position)
    {
        for(int i=0; i< specks.Count; i++)
        {
            specks[i].SetTargetPosition(position);
        }
    }

    public void MoveSpecks(Transform target)
    {
        for (int i = 0; i < specks.Count; i++)
        {
            specks[i].SetTarget(target);
        }
    }

}
