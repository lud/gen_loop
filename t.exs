defmodule T do

  use GenLoop
  def test(state) do
    ereceive state do
      x when is_atom(x) -> exit(:normal)
      {other} -> exit(:not_tuple)
      _other -> exit(:fuck)
    after 1 -> :ok
    end
  end

end


