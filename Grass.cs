using UnityEngine;

public class Grass : Scenery {

    private Animator anim;
    public float minWaveTime = 1f;
    public float maxWaveTime = 4f;
    
    void Start()
    {
        anim = GetComponent<Animator>();
        Invoke("Animate", Random.Range(minWaveTime, maxWaveTime));
    }

    void Animate()
    {
        anim.SetTrigger("Wave");
    }
}
