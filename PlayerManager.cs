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

    private List<IController> controllers = new List<IController>();

    public void Register(IController controller)
    {
        controllers.Add(controller);
    }

    public void Deregister(IController controller)
    {
        controllers.Remove(controller);
    }

    public void TellControllers(System.Action<IController> action)
    {
        for(int i=0; i<controllers.Count; i++)
        {
            action(controllers[i]);
        }
    }

    public void TellController(int playerID, System.Action<IController> action)
    {
        action(controllers.Find(x => x.playerID == playerID));
    }

}
