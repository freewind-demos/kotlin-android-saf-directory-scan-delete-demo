package demos.safdir

import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import androidx.recyclerview.widget.RecyclerView
import demos.safdir.databinding.ItemFileRowBinding

class BrowseListAdapter(
    private val onOpenDir: (BrowseEntry.Dir) -> Unit,
    private val onDeleteFile: (BrowseEntry.FileItem) -> Unit,
) : RecyclerView.Adapter<BrowseListAdapter.VH>() {

    private val items = mutableListOf<BrowseEntry>()

    fun replaceAll(newItems: List<BrowseEntry>) {
        items.clear()
        items.addAll(newItems)
        notifyDataSetChanged()
    }

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): VH {
        val binding = ItemFileRowBinding.inflate(LayoutInflater.from(parent.context), parent, false)
        return VH(binding)
    }

    override fun onBindViewHolder(holder: VH, position: Int) {
        holder.bind(items[position])
    }

    override fun getItemCount(): Int = items.size

    inner class VH(
        private val binding: ItemFileRowBinding,
    ) : RecyclerView.ViewHolder(binding.root) {

        fun bind(entry: BrowseEntry) {
            when (entry) {
                is BrowseEntry.Dir -> {
                    binding.label.text = binding.root.context.getString(R.string.row_format_dir, entry.name)
                    binding.btnDelete.visibility = View.GONE
                    binding.root.setOnClickListener { onOpenDir(entry) }
                    binding.btnDelete.setOnClickListener(null)
                }
                is BrowseEntry.FileItem -> {
                    binding.label.text = entry.name
                    binding.btnDelete.visibility = View.VISIBLE
                    binding.root.setOnClickListener(null)
                    binding.btnDelete.setOnClickListener { onDeleteFile(entry) }
                }
            }
        }
    }
}
