using UnityEngine;
using UnityEngine.Advertisements;

public class AdvertisingManager : MonoBehaviour {

	public bool IsReady { get { return Advertisement.isReady() && (Time.time - lastAdvertisementTime > 60f || lastAdvertisementTime == 0); } }

	private float lastAdvertisementTime = 0;
    private MenuManager menuManager;

    void Awake()
	{
        menuManager = GetComponent<MenuManager>();
		if(Advertisement.isSupported)
		{
			Advertisement.allowPrecache = true;
			Advertisement.Initialize("131627335");
		}
	}

	public void PlayAdvertisement()
	{
		Advertisement.Show(null, new ShowOptions {
			pause = true,
			resultCallback = ShowResult => {
			}
		});

		lastAdvertisementTime = Time.time;
		menuManager.SpawnGiftFlys(false);
	}
}