using System.Collections.Generic;
using Soomla.Store;

public class StoreAssets : IStoreAssets {

	public int GetVersion()
	{
		return 0;
	}

	public VirtualCurrency[] GetCurrencies()
	{
		return new VirtualCurrency[] {FLY_CURRENCY};
	}

	public VirtualGood[] GetGoods()
	{
		return new VirtualGood[] {BUSINESS_FROG_LTVG, HOT_LAWYER_LTVG, INVISIBLE_MAN_LTVG, CROSSY_FROG_LTVG};
	}

	public VirtualCurrencyPack[] GetCurrencyPacks()
	{
		return new VirtualCurrencyPack[] {THOUSAND_FLY_PACK};
	}

	public VirtualCategory[] GetCategories()
	{
		return new VirtualCategory[] {GENERAL_CATEGORY};
	}

	#region Static Final Members

	public const string FLY_CURRENCY_ITEM_ID = "currency_flys";
	public const string THOUSANDFLY_PACK_PRODUCT_ID = "thousand_flys_pack";
	public const string BUSINESS_FROG_PRODUCT_ID = "business_frog";
	public const string INVISIBLE_MAN_PRODUCT_ID = "invisible_man";
	public const string HOT_LAWYER_PRODUCT_ID = "hot_lawyer";
	public const string CROSSY_FROG_PRODUCT_ID = "crossy_frog";

	#endregion Static Final Members

	#region Virtual Currency

	public static VirtualCurrency FLY_CURRENCY = new VirtualCurrency(
		"Fly",						// Name
		"",				 			// Description
		FLY_CURRENCY_ITEM_ID		// ID
	);

	public static VirtualCurrencyPack THOUSAND_FLY_PACK = new VirtualCurrencyPack(
		"1000 Flys",				// Name
		"Unlock Frogs Faster!",		// Description
		"flys_1000",				// Item ID
		1000,						// Number of currencies in pack
		FLY_CURRENCY_ITEM_ID,		// ID of currency
		new PurchaseWithMarket(THOUSANDFLY_PACK_PRODUCT_ID, 0.99)
	);

	#endregion Virtual Currency

	#region Virtual Goods

	public static VirtualGood BUSINESS_FROG_LTVG = new LifetimeVG(
		"Business Frog",			// Name
		"Get Down to Business",		// Description
		"4_business_frog",			// Item ID
		new PurchaseWithMarket(BUSINESS_FROG_PRODUCT_ID, 0.99)
	);

	public static VirtualGood HOT_LAWYER_LTVG = new LifetimeVG(
		"Hot Lawyer",				// Name
		"To Sue or Not to Sue",		// Description
		"5_hot_lawyer",				// Item ID
		new PurchaseWithMarket(HOT_LAWYER_PRODUCT_ID, 0.99)
		);

	public static VirtualGood INVISIBLE_MAN_LTVG = new LifetimeVG(
		"Invisible Man",			// Name
		"Without a Trace",			// Description
		"3_invisible_man",			// Item ID
		new PurchaseWithMarket(INVISIBLE_MAN_PRODUCT_ID, 0.99)
		);

	public static VirtualGood CROSSY_FROG_LTVG = new LifetimeVG(
		"Crossy Frog",				// Name
		"In homage to a new classic",// Description
		"6_crossy_frog",			// Item ID
		new PurchaseWithMarket(CROSSY_FROG_PRODUCT_ID, 0.99)
		);

	#endregion Virtual Goods

	#region Virtual Categories

	public static VirtualCategory GENERAL_CATEGORY = new VirtualCategory(
		"General", new List<string>(new string[] {})
	);
	
	#endregion Virtual Categories

}