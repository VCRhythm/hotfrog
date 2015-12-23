using UnityEngine;
using UnityEngine.Advertisements;

public class AdvertisingManager : MonoBehaviour {

    public bool isReady { get { return Advertisement.IsReady() && (Time.time - lastAdvertisementTime > 60f || lastAdvertisementTime == 0); } }

    private float lastAdvertisementTime = 0;
    private MenuManager menuManager;

    void Awake()
    {
        menuManager = GetComponent<MenuManager>();
    }

    public void PlayAdvertisement()
    {
        Advertisement.Show(null, new ShowOptions {
            resultCallback = RewardViewing
        });
    }

    void RewardViewing(ShowResult showResult)
    {
        switch(showResult)
        {
            case ShowResult.Finished:
                lastAdvertisementTime = Time.time;
                menuManager.SpawnGiftFlys(false);
                break;
            default:
                break;
        }
        
    }
}