using UnityEngine;
using System;

[RequireComponent(typeof(Frog))]
public class FrogAI : Controller
{
    public override bool CanTouch
    {
        get
        {
            throw new NotImplementedException();
        }

        set
        {
            throw new NotImplementedException();
        }
    }

    public override bool isPlaying
    {
        get
        {
            throw new NotImplementedException();
        }

        set
        {
            throw new NotImplementedException();
        }
    }

    public override int playerID
    {
        get
        {
            throw new NotImplementedException();
        }

        set
        {
            throw new NotImplementedException();
        }
    }

    public override void AddToTongueCatchActions(Action action)
    {
        throw new NotImplementedException();
    }

    public override void CollectFly()
    {
        throw new NotImplementedException();
    }

    public override void PlayLevel()
    {
        throw new NotImplementedException();
    }

    public override void StartLevel()
    {
        throw new NotImplementedException();
    }
}
