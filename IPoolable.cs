public interface IPoolable {
	ObjectPool Pool {get; set;}
	void Destroy();
}
