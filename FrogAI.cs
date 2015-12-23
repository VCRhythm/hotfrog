using UnityEngine;

public class FrogAI : Controller
{
    private float lastDecisionTime = 0;
    private float nextDecisionTime = 1f;
    private float screenWidth;
    private float screenHeight;

    protected override void Start()
    {
        base.Start();

        SetFrog(GetComponentInChildren<Frog>());
        PlayLevel();

        screenHeight = Camera.main.orthographicSize;
        screenWidth = screenHeight * (Screen.height / Screen.width) *.5f;
    }

    void Update()
    {
        if (!CanTouch) return;

        MoveLimbs();

        if(Time.time >= lastDecisionTime + nextDecisionTime)
        {
            Vector2 worldPosition = new Vector2(Random.Range(-screenWidth, screenWidth), Random.Range(-screenHeight, screenHeight) );
            
            CheckTouch(worldPosition, 0);
            lastDecisionTime = Time.time;
        }
    }

    public override void CollectFly()
    {
        return;
    }

    public override void AteStartBug()
    {
        return;
    }
}
