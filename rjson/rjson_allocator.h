#include "luasandbox/heka/sandbox.h"
#include <rapidjson/allocators.h>

class SandboxMemoryAllocator {
public:
    size_t current_capacity = 0;
    static const bool kNeedFree = false;    //!< Tell users that no need to call Free() with this allocator. (concept Allocator)
    /*! No-args constructor. Invoked in some rapidjson internals, will result in untracked memory usage.
    */
    SandboxMemoryAllocator() :
    chunkHead_(0), chunk_capacity_(kDefaultChunkCapacity), baseAllocator_(0), ownBaseAllocator_(0), hsb_(0)
    {
    }

    //! Constructor with memory limit.
    /*! \param limit The size of memory chunk. The default is kDefaultChunkSize.
        \param baseAllocator The allocator for allocating memory chunks.
    */
    SandboxMemoryAllocator(lsb_heka_sandbox *hsb) :
    chunkHead_(0), chunk_capacity_(kDefaultChunkCapacity), baseAllocator_(0), ownBaseAllocator_(0), hsb_(hsb)
    {
    }

    //! Destructor.
    /*! This deallocates all memory chunks, excluding the user-supplied buffer.
    */
    ~SandboxMemoryAllocator() {
        Clear();
        RAPIDJSON_DELETE(ownBaseAllocator_);
    }

    //! Deallocates all memory chunks.
    void Clear() {
        while (chunkHead_) {
            ChunkHeader* next = chunkHead_->next;
            baseAllocator_->Free(chunkHead_);
            chunkHead_ = next;
        }
        UpdateCapacity(0);
    }

    //! Computes the total capacity of allocated memory chunks.
    /*! \return total capacity in bytes.
    */
    size_t Capacity() const {
      return current_capacity;
    }

    //! Computes the memory blocks allocated.
    /*! \return total used bytes.
    */
    size_t Size() const {
        size_t size = 0;
        for (ChunkHeader* c = chunkHead_; c != 0; c = c->next)
            size += c->size;
        return size;
    }

    //! Allocates a memory block. (concept Allocator)
    void* Malloc(size_t size) {
        if (!size)
            return NULL;

        size = RAPIDJSON_ALIGN(size);
        if (chunkHead_ == 0 || chunkHead_->size + size > chunkHead_->capacity)
            if (!AddChunk(chunk_capacity_ > size ? chunk_capacity_ : size))
                return NULL;

        void *buffer = reinterpret_cast<char *>(chunkHead_) + RAPIDJSON_ALIGN(sizeof(ChunkHeader)) + chunkHead_->size;
        chunkHead_->size += size;
        return buffer;
    }

    //! Resizes a memory block (concept Allocator)
    void* Realloc(void* originalPtr, size_t originalSize, size_t newSize) {
        if (originalPtr == 0)
            return Malloc(newSize);

        if (newSize == 0)
            return NULL;

        originalSize = RAPIDJSON_ALIGN(originalSize);
        newSize = RAPIDJSON_ALIGN(newSize);

        // Do not shrink if new size is smaller than original
        if (originalSize >= newSize)
            return originalPtr;

        // Simply expand it if it is the last allocation and there is sufficient space
        if (originalPtr == reinterpret_cast<char *>(chunkHead_) + RAPIDJSON_ALIGN(sizeof(ChunkHeader)) + chunkHead_->size - originalSize) {
            size_t increment = static_cast<size_t>(newSize - originalSize);
            if (chunkHead_->size + increment <= chunkHead_->capacity) {
                chunkHead_->size += increment;
                return originalPtr;
            }
        }

        // Realloc process: allocate and copy memory, do not free original buffer.
        if (void* newBuffer = Malloc(newSize)) {
            if (originalSize)
                std::memcpy(newBuffer, originalPtr, originalSize);
            return newBuffer;
        }
        else
            return NULL;
    }

    //! Frees a memory block (concept Allocator)
    static void Free(void *ptr) { (void)ptr; } // Do nothing

private:
    //! Copy constructor is not permitted.
    SandboxMemoryAllocator(const SandboxMemoryAllocator& rhs) /* = delete */;
    //! Copy assignment operator is not permitted.
    SandboxMemoryAllocator& operator=(const SandboxMemoryAllocator& rhs) /* = delete */;

    //! Creates a new chunk.
    /*! \param capacity Capacity of the chunk in bytes.
        \return true if success.
    */
    bool AddChunk(size_t capacity) {
        if (!baseAllocator_)
            ownBaseAllocator_ = baseAllocator_ = RAPIDJSON_NEW(rapidjson::CrtAllocator)();
        UpdateCapacity(current_capacity + capacity);
        if (ChunkHeader* chunk = reinterpret_cast<ChunkHeader*>(baseAllocator_->Malloc(RAPIDJSON_ALIGN(sizeof(ChunkHeader)) + capacity))) {
            chunk->capacity = capacity;
            chunk->size = 0;
            chunk->next = chunkHead_;
            chunkHead_ =  chunk;
            return true;
        }
        else
            return false;
    }

    void UpdateCapacity(size_t capacity) {
      if (hsb_) {
        lsb_heka_adjust_ext_memory_usage(hsb_, capacity - current_capacity);
        current_capacity = capacity;
      }
    }

    static const int kDefaultChunkCapacity = 64 * 1024; //!< Default chunk capacity.

    //! Chunk header for perpending to each chunk.
    /*! Chunks are stored as a singly linked list.
    */
    struct ChunkHeader {
        size_t capacity;    //!< Capacity of the chunk in bytes (excluding the header itself).
        size_t size;        //!< Current size of allocated memory in bytes.
        ChunkHeader *next;  //!< Next chunk in the linked list.
    };

    ChunkHeader *chunkHead_;    //!< Head of the chunk linked-list. Only the head chunk serves allocation.
    size_t chunk_capacity_;     //!< The minimum capacity of chunk when they are allocated.
    rapidjson::CrtAllocator* baseAllocator_;  //!< base allocator for allocating memory chunks.
    rapidjson::CrtAllocator* ownBaseAllocator_;   //!< base allocator created by this object.
    lsb_heka_sandbox *hsb_;
};
