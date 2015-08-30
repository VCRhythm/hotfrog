using UnityEngine;
using UnityEngine.UI;
using TMPro;
using System.Collections;
using DG.Tweening;

public class MenuManager : MonoBehaviour {

    public TextMeshProUGUI pausePrefab;
    public GameObject tameFlyNetPrefab;
    public Bug startGameBugPrefab;
    private Bug startBug;

    public RectTransform newFrogTextPrefab;
    public RectTransform tryAgainTextPrefab;

    private IController controller;
    private PurchaseManager purchaseManager;
    private FrogPackages frogPackages;
    private AdvertisingManager advertisingManager;
    private VariableManager variableManager;
    private HUD hud;

    private bool touchState;
	private bool touchStateIsSet = false;

    public bool IsShowingFrogName
    {
        set
        {
            frogName.DOFade(value ? 1 : 0, 0);
        }
    }

    private bool isShowingMainMenu = false;
	private bool IsShowingMainMenu
	{ 
		set 
		{
			if(value && !isShowingMainMenu)
			{
				frogPackages.isViewingAllFrogs = false;
				titleTransform.gameObject.SetActive(true);
				mainMenu.interactable = true;
				mainMenu.blocksRaycasts = true;
				if(mainMenu.alpha == 0)	mainMenu.DOFade(1, 1.5f);
				flyToGoText.Clear ();
				AnimateMainMenu(true);
				isShowingMainMenu = value;
			}
			else if(isShowingMainMenu && !value)
			{
				AnimateMainMenu(false);
				//mainMenu.alpha = 0; 
				mainMenu.interactable = false;
				mainMenu.blocksRaycasts = false;
				isShowingMainMenu = value;
			}
		} 
	}

	private bool IsShowingSettings
	{
		set
		{
			if(value)
			{
				settingsMenu.interactable = true;
				settingsMenu.blocksRaycasts = true;
				settingsMenu.alpha = 1;
			}
			else
			{
				variableManager.SaveSettings();
				settingsMenu.interactable = false;
				settingsMenu.blocksRaycasts = false;
				settingsMenu.alpha = 0;
			}
		}
	}

	private bool isShowingArrowPanel = true;
	private bool IsShowingArrowPanel
	{
		set
		{
			if(value)
			{
				if(!isShowingArrowPanel)
				{
					purchaseManager.StartService();
					arrowPanelCG.alpha = 1;
					arrowPanelCG.interactable = true;
					arrowPanelCG.blocksRaycasts = true;
					AnimateArrowPanel(true);
				}
			}
			else if(!value && isShowingArrowPanel)
			{
				purchaseManager.StopService();
//				arrowPanelCG.alpha = 0;
				arrowPanelCG.interactable = false;
				arrowPanelCG.blocksRaycasts = false;
				AnimateArrowPanel(false);
			}

			isShowingArrowPanel = value;
		}
	}

	private bool canSpendFlys = false;
	private bool CanSpendFlys
	{
		set
		{
			canSpendFlys = value;
			if(value)
			{
				UpdateFlyToGoText();
			}
			else
			{
				hud.canChangeFlyCount = true;
				hud.UpdateFlyCount();
				flyToGoText.Clear ();
				flyButton.interactable = false;
				flyPanelCG.interactable = false;
				flyPanelCG.blocksRaycasts = false;
				flyTextAnimator.SetBool("IsAnimating", false);
			}
		}
	}
	
	public bool IsShowingReturnPanel
	{
		set
		{
			if(value)
			{
				AnimateReturnPanel(false);
				returnPanel.alpha = 1;
				returnPanel.interactable = true;
				returnPanel.blocksRaycasts = true;
			}
			else
			{
				//returnPanel.alpha = 0;
				AnimateReturnPanel(true);
				returnPanel.interactable = false;
				returnPanel.blocksRaycasts = false;
			}
		}
	}

	private bool IsShowingHUD
	{
		set
		{
			if(value)
			{
				hudCanvas.alpha = 1;
			}
			else
			{
				qualityCountPanelCG.alpha = 0;
				hudCanvas.alpha = 0;
			}
		}
	}
	
	private bool IsShowingEndGamePanel
	{
		get { return endGamePanel.alpha == 1; }
		set
		{
			if(value)
			{
				endGamePanel.alpha = 1;
				endGamePanel.interactable = true;
				endGamePanel.blocksRaycasts = true;
				ShowGiftButton();
			}
			else
			{
				purchaseManager.StopService();
				endGamePanel.alpha = 0;
				endGamePanel.interactable = false;
				endGamePanel.blocksRaycasts = false;
			}
		}
	}

	private bool IsShowingGiftsButton
	{
		set
		{
			if(value)
			{
				giftButton.SetActive(true);
				adButton.SetActive(false);
				buyButtonObject.SetActive(false);
			}
			else
			{
				giftButton.SetActive(false);
				float rand = Random.value;
				if(rand > 0.6f && advertisingManager.IsReady)
				{
					adButton.SetActive(true);
					buyButtonObject.SetActive(false);
					timeUntilGiftText.lineSpacing = 400;
					timeUntilGiftText.color = Color.white;
					timeUntilGiftText.SetText("EARN FLYS!");
				}
				else if(rand > 0.3f && SetUpBuyButton())
				{
					purchaseManager.StartService();
					buyButtonObject.SetActive(true);
					adButton.SetActive(false);
				}
				else
				{
					SetTimeUntilGiftText();
					adButton.SetActive(false);
					buyButtonObject.SetActive(false);
				}
			}
		}
	}

	private RectTransform canvas;
	private RectTransform titleTransform;
	private CanvasGroup mainMenu;
	private CanvasGroup settingsMenu;
	private RectTransform frogButton;
	private RectTransform settingsButton;
	private RectTransform returnButton;

	private CanvasGroup hudCanvas;
	private RectTransform hudRect;
	private TextMeshProUGUI highScoreText;
	private RectTransform qualityCountPanel;
	private CanvasGroup qualityCountPanelCG;
	private TextMeshProUGUI perfectCount;
	private TextMeshProUGUI greatCount;
	private TextMeshProUGUI okCount;

	private CanvasGroup arrowPanelCG;
	private RectTransform arrowPanel;
	private TextMeshProUGUI frogName;
	private CanvasGroup returnPanel;
    private GameObject arrowPanelBuyButton;


	private Button flyButton;
	private CanvasGroup flyPanelCG;
	private Animator flyTextAnimator;
	private TextMeshProUGUI flyCount;
	private TextMeshProUGUI flyToGoText;

	private CanvasGroup endGamePanel;
	private GameObject giftButton;
	private TextMeshProUGUI timeUntilGiftText;
	private Color freeGiftTextColor = new Color(1f, .8f, 0);
	private Color buyTextColor = new Color(.28f, 1f, .61f);
	private GameObject adButton;
	private GameObject buyButtonObject;
	private Button buyButton;
	private Image buyButtonImage;
	private TextMeshProUGUI buyButtonText;
	private int frogCost = 100;

	private GameObject tameFlyNet;
    private Vector2 flyIconPosition;

	private float screenWidth = (float)Screen.width / Screen.height * 50;

	private TextMeshProUGUI pauseText;
	private Toggle musicToggle;

	private Lava lava;

	void Awake()
	{
        controller = transform.parent.GetComponentInChildren(typeof(IController)) as IController;
        purchaseManager = transform.parent.FindChild("SOOMLA").GetComponent<PurchaseManager>();
        frogPackages = GetComponentInParent<FrogPackages>();
        variableManager = GetComponentInParent<VariableManager>();
        advertisingManager = GetComponentInParent<AdvertisingManager>();
		canvas = GetComponent<RectTransform>();
		titleTransform = canvas.FindChild("Title").GetComponent<RectTransform>();

		mainMenu = canvas.FindChild("MainMenu").GetComponent<CanvasGroup>();
		frogButton = mainMenu.transform.FindChild("FrogButton").GetComponent<RectTransform>();
		settingsButton = mainMenu.transform.FindChild("SettingsButton").GetComponent<RectTransform>();

		settingsMenu = canvas.FindChild("SettingsPanel").GetComponent<CanvasGroup>();
		musicToggle = settingsMenu.transform.GetChild(0).FindChild("MusicToggle").GetComponent<Toggle>();

        hud = transform.FindChild("HUD").GetComponent<HUD>();
        hudCanvas = hud.GetComponent<CanvasGroup>();
		hudRect = hud.GetComponent<RectTransform>();

		qualityCountPanelCG = canvas.FindChild("QualityCountPanel").GetComponent<CanvasGroup>();
		qualityCountPanel = qualityCountPanelCG.GetComponent<RectTransform>();
		perfectCount = qualityCountPanel.FindChild("PerfectCount").GetComponent<TextMeshProUGUI>();
		greatCount = qualityCountPanel.FindChild("GreatCount").GetComponent<TextMeshProUGUI>();;
		okCount = qualityCountPanel.FindChild("OKCount").GetComponent<TextMeshProUGUI>();;

        flyIconPosition = new Vector2(screenWidth, 50);
		flyButton = canvas.FindChild ("FlyPanel").GetComponent<Button>();
		flyPanelCG = flyButton.GetComponent<CanvasGroup>();
		flyTextAnimator = flyButton.transform.FindChild("FlyCount").GetComponent<Animator>();
		flyCount = flyButton.transform.FindChild("FlyCount").GetComponent<TextMeshProUGUI>();
        flyToGoText = flyButton.transform.FindChild("ToGoText").GetComponent<TextMeshProUGUI>();
		tameFlyNet = Instantiate(tameFlyNetPrefab, flyIconPosition, Quaternion.identity) as GameObject;

		arrowPanelCG = canvas.FindChild("ArrowPanel").GetComponent<CanvasGroup>();
		arrowPanel = arrowPanelCG.GetComponent<RectTransform>();
		frogName = arrowPanel.FindChild("FrogName").GetComponent<TextMeshProUGUI>();
        arrowPanelBuyButton = arrowPanel.FindChild("BuyButton").gameObject;

        returnPanel = canvas.FindChild("ReturnPanel").GetComponent<CanvasGroup>();
		returnButton = returnPanel.transform.FindChild("ReturnButton").GetComponent<RectTransform>();

		Transform endGameTransform = canvas.FindChild("EndGamePanel");
		endGamePanel = endGameTransform.GetComponent<CanvasGroup>();
		giftButton = endGameTransform.FindChild("GiftsButton").gameObject;
		adButton = endGameTransform.FindChild("AdsButton").gameObject;

		timeUntilGiftText = endGameTransform.FindChild("TimeUntilGift").GetComponent<TextMeshProUGUI>();

		buyButtonObject = endGameTransform.FindChild("BuyButton").gameObject;
		buyButton = buyButtonObject.GetComponent<Button>();
		buyButtonText = buyButton.transform.FindChild("Text").GetComponent<TextMeshProUGUI>();
		buyButtonImage = buyButton.transform.FindChild("Image").GetComponent<Image>();

		lava = FindObjectOfType<Lava>();
	}

	void Start()
	{
        InitialSetup();
		musicToggle.isOn = variableManager.IsPlayingMusic;
	}

	void OnApplicationFocus(bool focusStatus) 
	{
		if(!focusStatus)
		{
			StopCoroutine("Resume");

			if(!touchStateIsSet)
			{
				touchState = controller.CanTouch;
				touchStateIsSet = true;
			}
			controller.CanTouch = false;

			if(pauseText != null) Destroy (pauseText.gameObject);
			pauseText = Instantiate (pausePrefab) as TextMeshProUGUI;
			pauseText.transform.SetParent(canvas.GetComponent<RectTransform>(), false);

			Time.timeScale = 0;
		}
		else
		{
			StartCoroutine("Resume");
		}
	}

	#region Functions

	public void ShowSettings()
	{
		CanSpendFlys = false;
		IsShowingFrogName = false;
		IsShowingEndGamePanel = false;
		IsShowingHUD = false;
		IsShowingArrowPanel = false;
		IsShowingMainMenu = false;

		PlaySelectSound();

		IsShowingSettings = true;
		IsShowingReturnPanel = true;
		
		ShowStartGameFly(new Vector4(.3f, .35f, 1.5f, .35f));
	}

	public void ShowFrogs()
	{
		PlaySelectSound();
		lava.Reset();

		IsShowingFrogName = true;
		IsShowingHUD = false;
		IsShowingEndGamePanel = false;
		IsShowingMainMenu = false;

		FrogPackages.Instance.RaiseFrog();
		FrogPackages.Instance.isViewingAllFrogs = true;
		IsShowingArrowPanel = true;
		IsShowingReturnPanel = true;
		CanSpendFlys = true;

		ShowStartGameFly(new Vector4(.5f, .35f, 1f, .35f));
	}

	public void SpendFlys()
	{
		Debug.Log ("Spend Flys");
		lava.Reset();

		if(tameFlyNet.gameObject.activeSelf)
			tameFlyNet.gameObject.SetActive(false);

		CanSpendFlys = false;

		StartCoroutine(hud.ChangeBugCount(-frogCost));

		IsShowingReturnPanel = false;
		IsShowingArrowPanel = false;
		IsShowingEndGamePanel = false;
		HideStartFly();
		IsShowingHUD = false;

		SpawnManager.Instance.SpawnFlyBundle(frogCost, flyIconPosition, controller.playerID);
		FrogPackages.Instance.LowerAndOpenRandomFrog(true);

		Invoke ("ShowReturnPanel", 3f);
	}

	public void GiftFlys()
	{
		lava.Reset();

		CanSpendFlys = false;

		GiftManager.Instance.IncreaseGiftSeed();
		IsShowingArrowPanel = false;
		IsShowingEndGamePanel = false;
		HideStartFly();
		IsShowingHUD = false;

		SpawnGiftFlys(true);
	}
	
	public void ShowMainMenu(bool playSound)
	{
		lava.Reset();

		CanSpendFlys = false;
		IsShowingFrogName = false;
		IsShowingEndGamePanel = false;
		IsShowingHUD = false;
		IsShowingArrowPanel = false;
		IsShowingReturnPanel = false;
		IsShowingSettings = false;

		if(playSound) PlaySelectSound();

		IsShowingMainMenu = true;

		ShowStartGameFly(new Vector4(0.5f, 0.35f, 0.6f, 0.35f));
		FrogPackages.Instance.MakeSureFrogIsPurchased();
	}

	public void StartGame()
	{
		PlaySelectSound();

		FrogPackages.Instance.MakeSureFrogIsPurchased();
		lava.Reset();

		IsShowingSettings = false;
		IsShowingArrowPanel = false;
		IsShowingMainMenu = false;
		IsShowingEndGamePanel = false;
		HideStartFly();
		IsShowingReturnPanel = true;
		CanSpendFlys = false;

		IsShowingHUD = true;
		MoveHUD(false);

		LevelManager.Instance.ShowIntroAndStartLevel();
	}
	
	public void ShowAd()
	{
		CanSpendFlys = false;
		HideStartFly();
		IsShowingEndGamePanel = false;
		IsShowingHUD = false;

		advertisingManager.PlayAdvertisement();
	}

	public void SpawnGiftFlys(bool isGift, int amountOverride = -1)
	{
		lava.Reset();

		if(!tameFlyNet.gameObject.activeSelf)
			tameFlyNet.gameObject.SetActive(true);

		int giftAmount = amountOverride >= 0 ? amountOverride : (isGift ? Random.Range(60, 100) : Random.Range(15, 35));

		SpawnManager.Instance.SpawnFlyBundle(giftAmount, -flyIconPosition, controller.playerID);

		frogPackages.RaiseFrog();
		Invoke ("ShowReturnPanel", 3f);
	}

	public void Quit()
	{
		PlaySelectSound();
		Application.Quit();
	}
	
	public void ShowEndGamePanel()
	{
		MoveHUD(true);

		CanSpendFlys = true;
		IsShowingEndGamePanel = true;
		ShowStartGameFly(new Vector4(1.5f, .35f, .3f, 1f));
	}

	public void DisableBuyButton(bool hasProblem)
	{
		buyButton.onClick.RemoveAllListeners();
		if(hasProblem)
			buyButtonText.SetText("Try Again Later");
		else
		{
			buyButtonText.SetText("NICE!");
		}
	}

	public void InitialSetup()
	{
		flyPanelCG.GetComponent<Animator>().SetTrigger("ShowPanel");
		ShowMainMenu(false);
	}
		
	public void UpdateFlyToGoText()
	{
		if(canSpendFlys)
		{
			int bugsLeft = frogCost - hud.BugsCaught;
			
			if(bugsLeft <= 0)
			{
				flyButton.interactable = true;
				flyPanelCG.interactable = true;
				flyPanelCG.blocksRaycasts = true;
				
				flyCount.SetText("Win a frog!");
				hud.canChangeFlyCount = false;
				flyTextAnimator.SetBool("IsAnimating", true);
				flyToGoText.Clear();
			}
			else
			{
				flyButton.interactable = false;
				flyPanelCG.interactable = false;
				flyPanelCG.blocksRaycasts = false;
				flyTextAnimator.SetBool("IsAnimating", false);
				flyToGoText.SetText("{0} To Go!", bugsLeft);
			}
		}
	}

	public void SetGrabStats(Vector4i qualityStats)
	{
		int total = Mathf.Max (qualityStats.x + qualityStats.y + qualityStats.z, 1);

		perfectCount.SetText("{0}% Perfect", (qualityStats.z / (float)total) * 100);
		greatCount.SetText("{0}% Great", (qualityStats.y / (float)total) * 100);
		okCount.SetText("{0}% OK", (qualityStats.x / (float)total) * 100);
	}

    public void ShowArrowPanelBuyButton(bool isTrue)
    {
        arrowPanelBuyButton.SetActive(isTrue);
    }

    public IEnumerator ShowFrogName(float waitTime, string name, bool canCelebrate, bool hasPackage)
    {
        frogName.Clear();
        yield return new WaitForSeconds(waitTime);

        frogName.color = hasPackage || canCelebrate ? Color.white : Color.red;
        frogName.SetText(name);

        if (canCelebrate)
        {
            CelebrateNew(!hasPackage);
        }
    }


    #endregion Functions

    #region Private Functions

    private void CelebrateNew(bool isNew)
    {
        AudioManager.Instance.PlayForAll(isNew ? AudioManager.Instance.newSound : AudioManager.Instance.missSound);
        RectTransform newFrogText = Instantiate(isNew ? newFrogTextPrefab : tryAgainTextPrefab) as RectTransform;
        newFrogText.SetParent(canvas, true);
        newFrogText.anchoredPosition = Vector2.zero;

        Destroy(newFrogText.gameObject, 2f);
    }

    private IEnumerator Resume()
	{
		if(pauseText != null)
		{
			if(!controller.CanTouch)
			{
				float pauseEndTime;
				for(int i=3; i >= 1; i--)
				{
					AudioManager.Instance.PlayForAll(AudioManager.Instance.blinkSound);
					pauseText.SetText("{0}", i);
					pauseEndTime = Time.realtimeSinceStartup + 1f;

					while(Time.realtimeSinceStartup < pauseEndTime)
						yield return null;
				}
			}
			if(pauseText != null) Destroy (pauseText.gameObject);
			controller.CanTouch = touchState;
			touchStateIsSet = false;
			Time.timeScale = 1;
		}
	}

	private void ShowStartGameFly(Vector4 barriers)
	{
		if(startBug == null)
		{
			startBug = Instantiate(startGameBugPrefab, new Vector3(0,0,-1), Quaternion.identity) as Bug;
			startBug.screenOffset = barriers;
			startBug.enabled = true;
		}
	}

	private void HideStartFly()
	{
		if(startBug != null) startBug.Leave();
		startBug = null;
	}

	private void ShowGiftButton()
	{
		bool canShowGift = GiftManager.Instance.CanShowGift();

		if(canShowGift)
		{
			timeUntilGiftText.lineSpacing = 400;
			timeUntilGiftText.color = freeGiftTextColor;
			timeUntilGiftText.SetText("FREE GIFT!");
		}

		IsShowingGiftsButton = canShowGift;
	}

	private void SetTimeUntilGiftText()
	{
		timeUntilGiftText.lineSpacing = 0;
		timeUntilGiftText.color = Color.white;
		float minutesUntilGift = GiftManager.Instance.MinutesUntilGift();
		if(minutesUntilGift < 10f)
			timeUntilGiftText.SetText("Gift in\n{0}:0{1}", GiftManager.Instance.HoursUntilGift(), minutesUntilGift);
		else
			timeUntilGiftText.SetText("Gift in\n{0}:{1}", GiftManager.Instance.HoursUntilGift(), minutesUntilGift);
	}

	private void MoveHUD(bool isMovingUp)
	{
		if(isMovingUp)
		{
			ShowQualityStats(true);
			DOTween.To (UpdateHUDPosition, isMovingUp ? 0 : 0.83f, isMovingUp ? 0.83f : 0, 1f).SetEase(Ease.OutBack).SetDelay(0.5f);
		}
		else if(!isMovingUp)
		{
			ShowQualityStats(false);
			DOTween.To (UpdateHUDPosition, isMovingUp ? 0 : 0.83f, isMovingUp ? 0.83f : 0, 1f).SetEase(Ease.OutBack);
		}
	}
	
	private void ShowQualityStats(bool isAppearing)
	{
		qualityCountPanelCG.DOFade(isAppearing ? 1f : 0, isAppearing ? 1f : 0);

		if(isAppearing)
			DOTween.To (UpdateQualityCountPanel, 0.5f, 0, 1f).SetEase(Ease.OutBack);
		else
			DOTween.To (UpdateQualityCountPanel, 0, 0.5f, 0f);
	}

	private void UpdateQualityCountPanel(float value)
	{
		qualityCountPanel.anchorMin = new Vector2(value, 0);
		qualityCountPanel.anchorMax = new Vector2(value, 0);
		qualityCountPanel.pivot = new Vector2(value, 0);
	}

	private void UpdateHUDPosition(float value)
	{
		hudRect.anchorMin = new Vector2(0, value);
		hudRect.anchorMax = new Vector2(1f, value);
		hudRect.pivot = new Vector2(0.5f, value);
		hudRect.anchoredPosition = new Vector2(0, 50 - value * 50);
	}

	private void PlaySelectSound()
	{
		AudioManager.Instance.PlayForAll (AudioManager.Instance.selectSound);
	}

	private void StopAllTweens()
	{
		DOTween.Clear();
	}

	private void AnimateMainMenu(bool isEntering)
	{
		titleTransform.DOKill();

		DOTween.To (UpdateTitlePosition, isEntering ? -0.75f : 1.5f, isEntering ? 1.5f : -0.75f, 1f).SetEase(Ease.OutBack);
//		frogButton.DOMove(new Vector3(frogButton.position.x - offsetStart, frogButton.position.y, frogButton.position.z), 1f).SetEase(Ease.OutBounce).From();
	}

	private void AnimateReturnPanel(bool isEntering)
	{
		returnButton.DOKill();

		DOTween.To (UpdateReturnPanel, isEntering ? -0.75f : 1.5f, isEntering ? 1.5f : -0.75f, 1f).SetEase(Ease.OutBack);
	}

	private void UpdateTitlePosition(float value)
	{
		titleTransform.pivot = new Vector2(0.5f, value);
		frogButton.pivot = new Vector2(1.5f - value, 0);
		settingsButton.pivot = new Vector2(value - .5f, 0);
		//UpdateReturnPanel(value);
	}

	private void UpdateReturnPanel(float value)
	{
		returnButton.pivot = new Vector2(0, value +.75f);
	}

	private void AnimateArrowPanel(bool isEntering)
	{
		DOTween.To(UpdateArrowPanel, isEntering ? 1.5f : 0, isEntering ? 0 : 1.5f, 1f).SetEase(Ease.OutBack);
	}

	private void UpdateArrowPanel(float value)
	{
		arrowPanel.pivot = new Vector2(0, value);
	}

	private void ShowReturnPanel()
	{
		CanSpendFlys = true;
		FrogPackages.Instance.isViewingAllFrogs = true;
		IsShowingArrowPanel = true;
		IsShowingFrogName = true;
		IsShowingReturnPanel = true;

		ShowStartGameFly(new Vector4(.5f, .35f, 1f, .35f));
	}

	private bool SetUpBuyButton()
	{
		Frog frog = FrogPackages.Instance.GetRandomClosedFrogForEndGamePanel();
		if(frog != null)
		{
			timeUntilGiftText.lineSpacing = 400;
			timeUntilGiftText.color = buyTextColor;
			timeUntilGiftText.SetText("GET A FROG!");

			buyButtonText.SetText("$0.99");
			buyButtonImage.sprite = frog.ThumbnailSprite;
			buyButton.onClick.AddListener(() => { purchaseManager.Purchase(frog); });
			return true;
		}
		return false;
	}

    private void MakeActionText(RectTransform prefab)
    {
        RectTransform instantiated = Instantiate(prefab) as RectTransform;
        instantiated.SetParent(canvas, false);
        Destroy(instantiated.gameObject, 2f);
    }

    #endregion Private Functions
}
