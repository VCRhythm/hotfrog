using UnityEngine;
using System.Collections.Generic;
using Soomla.Store;
using System.Text.RegularExpressions;

public class PurchaseManager : MonoBehaviour {

	public RectTransform restoredTextPrefab;
	public bool isUsingStore = true;
	private bool hasStarted = false;
	private StoreAssets assets;
    private MenuManager menuManager;
    private HUD hud;
    private FrogPackages frogPackages;
    
    void Awake()
    {
        frogPackages = GetComponent<FrogPackages>();
        hud = GetComponent<HUD>();
        menuManager = GetComponent<MenuManager>();
    }

	void Start()
	{
		if(isUsingStore)
		{
		assets = new StoreAssets();
		SoomlaStore.Initialize(assets);

		StoreEvents.OnCurrencyBalanceChanged += onCurrencyBalanceChanged;
		StoreEvents.OnMarketPurchase += onMarketPurchase;
		//StoreEvents.OnGoodBalanceChanged += OnGoodBalanceChanged;
		StoreEvents.OnMarketRefund += onMarketRefund;
		StoreEvents.OnUnexpectedStoreError += onUnexpectedStoreError;
		StoreEvents.OnRestoreTransactionsFinished += OnRestoreTransactionsFinished;

		if(FrogPackages.Instance.ResetPackagesOnStart)
			ClearPurchases();
		}
	}

	public void StartService()
	{
		if(!hasStarted)
		{
			hasStarted = true;
			SoomlaStore.StartIabServiceInBg();
		}
	}

	public void StopService()
	{
		if(hasStarted)
		{
			SoomlaStore.StartIabServiceInBg();
			hasStarted = false;
		}
	}

	public void Purchase(Frog frog)
	{
		string productID = frog.frogName.Replace(" ", "_").ToLower();
		SoomlaStore.BuyMarketItem(productID, "Purchase Complete");
	}

	public void onCurrencyBalanceChanged(VirtualCurrency virtualCurrency, int balance, int amountAdded)
	{
		if(amountAdded > 0)
			menuManager.SpawnGiftFlys(false, amountAdded);
		else
			hud.ChangeBugCount(amountAdded);
	}

	public void ClearPurchases()
	{
		VirtualGood[] virtualGoods = assets.GetGoods();
		foreach(VirtualGood good in virtualGoods)
		{
			good.ResetBalance(0);
			FrogPackages.Instance.LockPackage(GetID(good.ItemId));
		}
	}

//	public void OnGoodBalanceChanged(VirtualGood good, int balance, int amountAdded)
//	{
//		Debug.Log ("Balance changed");
//		int id = GetID(good.ItemId);
//		if(id > 0 && balance > 0)
//			FrogPackages.Instance.RestorePurchase(id);
		//else if(id > 0 && balance < 1)
		//	FrogPackages.Instance.LockPackage(id);
//	}

	public void onMarketPurchase(PurchasableVirtualItem pvi, string payload, Dictionary<string, string> extra)
	{
		int id = GetID(pvi.ItemId);
		if(id > 0 && pvi.GetBalance() > 0)
			frogPackages.PurchaseFrogFromStore(id);
	}
	
	public void onMarketRefund(PurchasableVirtualItem pvi)
	{
		int id = GetID(pvi.ItemId);

		if(id > 0)
			frogPackages.LockPackage(id);
	}

	public void onUnexpectedStoreError(int errorCode)
	{
		menuManager.DisableBuyButton(true);
        /*
        VERIFICATION_TIMEOUT(1) - app didn't receive validation response from server in time. Please, try again later.
        VERIFICATION_FAIL(2) - something is going wrong while SOOMLA tried to verify purchase.
        PURCHASE_FAIL(3) - something is going wrong while SOOMLA tried to make purchase.
        GENERAL(0) - other types of error. See details in app logs.
        */
	}

	public void OnRestoreTransactionsFinished(bool success)
	{
		if(success)
		{
			VirtualGood[] virtualGoods = assets.GetGoods();
			foreach(VirtualGood good in virtualGoods)
			{
				int id = GetID (good.ItemId);
				if(id > 0 && good.GetBalance() > 0)
				{
					Debug.Log ("Restoring: " + id);
					FrogPackages.Instance.RestorePurchase(id);
				}
				else
					FrogPackages.Instance.LockPackage(id);
			}
		}
	}

	private int GetID(string stringID)
	{
		int id;
		int.TryParse(Regex.Split(stringID, "_")[0], out id);
		if(id > 0 && id < 999)
			return id;
		else
			return -1;
	}
}