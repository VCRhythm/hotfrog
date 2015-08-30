using UnityEngine;

public interface IController  {
    int playerID { get; set; }
    bool isPlaying { get; set; }
    bool CanTouch { get; set; }

    void StartLevel();
    void PlayLevel();
    void SetFrog(Frog frog);
    void ForceRelease(Transform step);
    void CollectFly();
    void AddToTongueCatchActions(System.Action action);
}