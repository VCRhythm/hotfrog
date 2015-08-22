using UnityEngine;

public class Sun : MonoBehaviour {

    void Awake()
    {
        GetComponent<SpriteRenderer>().material.SetInt("_ZWrite", 10);
    }
}
