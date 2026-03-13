using UnityEngine;

namespace HotFrog.Entities
{
public class Grass : Scenery {

    private Animator anim;
    [SerializeField] private float minWaveTime = 1f;
    [SerializeField] private float maxWaveTime = 4f;

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
}
