using UnityEngine;
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

    private List<Controller> controllers = new List<Controller>();

    public void Register(Controller controller)
    {
        controllers.Add(controller);
    }

    public void Deregister(Controller controller)
    {
        controllers.Remove(controller);
    }

    public void TellControllers(System.Action<Controller> action)
    {
        for(int i=0; i<controllers.Count; i++)
        {
            action(controllers[i]);
        }
    }

    public void TellController(int playerID, System.Action<Controller> action)
    {
        Debug.Log(controllers.Count);
        Controller controller = controllers.Find(x => x.playerID == playerID);
        Debug.Log(controller + " action: " + action);
        action(controller);
    }

}
