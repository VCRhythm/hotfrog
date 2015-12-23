using UnityEngine;
using System;
using System.Collections.Generic;

public class ControllerManager : MonoBehaviour {

    // A singleton instance of this class
    private static ControllerManager instance;
    public static ControllerManager Instance
    {
        get
        {
            if (instance == null) instance = FindObjectOfType<ControllerManager>();
            return instance;
        }
    }

    public static int playerCount = 0;

    public bool anyPlaying
    {
        get
        {
            bool playing = false;
            for (int i = 0; i < controllers.Count; i++)
            {
                if (controllers[i].IsPlaying) playing = true;
            }
            return playing;
        }
    }

    public bool allCanPlay
    {
        get
        {
            bool playing = true;
            for(int i = 0; i < controllers.Count; i++)
            {
                if (!controllers[i].CanPlay) playing = false;
            }
            return playing;
        }
    }

    private List<Controller> controllers = new List<Controller>();

    public void Register(Controller controller)
    {
        controllers.Add(controller);
    }

    public void Deregister(Controller controller)
    {
        controllers.Remove(controller);
    }

    public void TellControllers(Action<Controller> action)
    {
        for(int i=0; i<controllers.Count; i++)
        {
            action(controllers[i]);
        }
    }

    public void TellController(int playerID, Action<Controller> action)
    {
        Controller controller = controllers.Find(x => x.ControllerID == playerID);
        action(controller);
    }

    public void TellController(Controller controller, Action<Controller> action)
    {
        action(controller);
    }
}
